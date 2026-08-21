#!/usr/bin/env bash
set -euo pipefail

# Discover a workload floating IP from the ops-runner without copying
# OpenStack admin credentials off the lab-host. The ops-runner SSHes to the
# lab-host and executes the OpenStack CLI there, where kolla-admin clouds.yaml
# already lives.

SERVER_NAME=${1:-}
AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_EXTERNAL_CIDR=${OPENSTACK_EXTERNAL_CIDR:-192.168.250.0/24}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}
DISCOVERY_ATTEMPTS=${DISCOVERY_ATTEMPTS:-60}
DISCOVERY_INTERVAL_SECONDS=${DISCOVERY_INTERVAL_SECONDS:-5}

if [[ -z "$SERVER_NAME" ]]; then
  echo "Usage: $0 <openstack-server-name>" >&2
  exit 2
fi

if [[ ! "$SERVER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid OpenStack server name: $SERVER_NAME" >&2
  exit 2
fi

python3 - "$LAB_HOST_PRIVATE_IP" "$OPENSTACK_EXTERNAL_CIDR" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
ipaddress.IPv4Network(sys.argv[2], strict=False)
PY

for binary in aws ssh python3; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

SSH_KEY=$(mktemp /tmp/private-banking-lab-host-key.XXXXXX)
KNOWN_HOSTS=$(mktemp /tmp/private-banking-lab-host-known-hosts.XXXXXX)
trap 'rm -f "$SSH_KEY" "$KNOWN_HOSTS"' EXIT

aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$LAB_SSH_KEY_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$SSH_KEY"
chmod 0600 "$SSH_KEY"

SSH_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
)

remote_addresses() {
  ssh "${SSH_OPTS[@]}" \
    "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
    "OS_CLIENT_CONFIG_FILE='${OPENSTACK_CLOUDS_FILE}' '${OPENSTACK_CLIENT}' --os-cloud '${OPENSTACK_CLOUD}' server show '${SERVER_NAME}' -f value -c addresses" \
    2>/dev/null
}

extract_external_ip() {
  python3 -c '
import ipaddress
import re
import sys

network = ipaddress.IPv4Network(sys.argv[1], strict=False)
addresses = sys.argv[2]
for candidate in re.findall(r"(?:\\d{1,3}\\.){3}\\d{1,3}", addresses):
    try:
        ip = ipaddress.IPv4Address(candidate)
    except ipaddress.AddressValueError:
        continue
    if ip in network:
        print(ip)
        raise SystemExit(0)
raise SystemExit(1)
' "$OPENSTACK_EXTERNAL_CIDR" "$1"
}

for attempt in $(seq 1 "$DISCOVERY_ATTEMPTS"); do
  addresses=$(remote_addresses || true)
  if [[ -n "$addresses" ]]; then
    floating_ip=$(extract_external_ip "$addresses" 2>/dev/null || true)
    if [[ -n "$floating_ip" ]]; then
      printf '%s\n' "$floating_ip"
      exit 0
    fi
  fi

  if (( attempt == 1 || attempt % 6 == 0 )); then
    printf 'Waiting for OpenStack floating IP of %s via lab-host %s (%d/%d)...\n' \
      "$SERVER_NAME" "$LAB_HOST_PRIVATE_IP" "$attempt" "$DISCOVERY_ATTEMPTS" >&2
  fi
  sleep "$DISCOVERY_INTERVAL_SECONDS"
done

echo "Unable to discover a floating IP for '$SERVER_NAME' in $OPENSTACK_EXTERNAL_CIDR." >&2
echo "Check that Terraform OpenStack completed and that the lab-host/OpenStack APIs are healthy." >&2
exit 1
