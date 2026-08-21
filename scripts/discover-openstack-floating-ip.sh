#!/usr/bin/env bash
set -euo pipefail

# Discover a workload floating IP from the ops-runner without copying
# OpenStack admin credentials off the lab-host. The ops-runner SSHes to the
# lab-host and executes the OpenStack CLI there, where kolla-admin clouds.yaml
# already lives.
#
# Important: fail fast when SSH/OpenStack itself is broken. Only the actual
# "port/FIP is not visible yet" condition is retried.

SERVER_NAME=${1:-}
AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_EXTERNAL_CIDR=${OPENSTACK_EXTERNAL_CIDR:-192.168.250.0/24}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}
DISCOVERY_ATTEMPTS=${DISCOVERY_ATTEMPTS:-24}
DISCOVERY_INTERVAL_SECONDS=${DISCOVERY_INTERVAL_SECONDS:-5}

if [[ -z "$SERVER_NAME" ]]; then
  echo "Usage: $0 <openstack-server-name>" >&2
  exit 2
fi

if [[ ! "$SERVER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid OpenStack server name: $SERVER_NAME" >&2
  exit 2
fi

PORT_NAME="${SERVER_NAME}-port"

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

remote_openstack() {
  local remote_cmd
  printf -v remote_cmd '%q ' \
    env "OS_CLIENT_CONFIG_FILE=$OPENSTACK_CLOUDS_FILE" \
    "$OPENSTACK_CLIENT" \
    --os-cloud "$OPENSTACK_CLOUD" \
    "$@"

  ssh "${SSH_OPTS[@]}" \
    "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
    "$remote_cmd"
}

# Do not turn SSH/auth/configuration failures into a misleading five-minute
# "waiting for floating IP" loop. Validate the control path once up front.
if ! ssh "${SSH_OPTS[@]}" \
  "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
  "test -x '$OPENSTACK_CLIENT' && test -r '$OPENSTACK_CLOUDS_FILE'"; then
  echo "Unable to reach a usable OpenStack client/clouds.yaml on lab-host $LAB_HOST_PRIVATE_IP." >&2
  echo "Check SSH access, $OPENSTACK_CLIENT and $OPENSTACK_CLOUDS_FILE on the lab-host." >&2
  exit 1
fi

if ! auth_check=$(remote_openstack token issue -f value -c id 2>&1); then
  echo "OpenStack authentication from the lab-host failed:" >&2
  printf '%s\n' "$auth_check" >&2
  exit 1
fi

is_external_ip() {
  python3 - "$OPENSTACK_EXTERNAL_CIDR" "$1" <<'PY'
import ipaddress
import sys
network = ipaddress.IPv4Network(sys.argv[1], strict=False)
try:
    ip = ipaddress.IPv4Address(sys.argv[2])
except ipaddress.AddressValueError:
    raise SystemExit(1)
raise SystemExit(0 if ip in network else 1)
PY
}

for attempt in $(seq 1 "$DISCOVERY_ATTEMPTS"); do
  # Terraform names the Neutron port <server-name>-port. Query Neutron directly
  # instead of parsing Nova's human-readable "addresses" field.
  port_id=$(remote_openstack port show "$PORT_NAME" -f value -c id 2>/dev/null || true)

  if [[ -n "$port_id" ]]; then
    floating_ip=$(
      remote_openstack floating ip list \
        --port "$port_id" \
        -f value \
        -c "Floating IP Address" 2>/dev/null \
        | awk 'NF {print $1; exit}' \
        || true
    )

    if [[ -n "$floating_ip" ]] && is_external_ip "$floating_ip"; then
      printf '%s\n' "$floating_ip"
      exit 0
    fi
  fi

  if (( attempt == 1 || attempt % 6 == 0 )); then
    printf 'Waiting for Neutron floating IP on port %s via lab-host %s (%d/%d)...\n' \
      "$PORT_NAME" "$LAB_HOST_PRIVATE_IP" "$attempt" "$DISCOVERY_ATTEMPTS" >&2
  fi
  sleep "$DISCOVERY_INTERVAL_SECONDS"
done

echo "Unable to discover a floating IP for '$SERVER_NAME' in $OPENSTACK_EXTERNAL_CIDR." >&2
echo "OpenStack SSH/authentication are healthy, but Neutron does not expose an associated FIP on '$PORT_NAME'." >&2
echo "Check the completed Terraform OpenStack run and: openstack floating ip list" >&2
exit 1
