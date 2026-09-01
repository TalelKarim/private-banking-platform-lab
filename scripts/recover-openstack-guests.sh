#!/usr/bin/env bash
set -euo pipefail

# Safety net in addition to Nova resume_guests_state_on_host_boot=true.
# It starts ONLY the known lab machines if they exist and are SHUTOFF. This is
# intentionally not "start every SHUTOFF server", so an intentionally stopped
# unrelated VM stays stopped.

AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}
WAIT_ATTEMPTS=${WAIT_ATTEMPTS:-60}
WAIT_INTERVAL_SECONDS=${WAIT_INTERVAL_SECONDS:-3}
OPENSTACK_READY_ATTEMPTS=${OPENSTACK_READY_ATTEMPTS:-60}
OPENSTACK_READY_INTERVAL_SECONDS=${OPENSTACK_READY_INTERVAL_SECONDS:-5}

DESIRED_SERVERS=(
  jenkins-controller
  jenkins-agent-01
  postgresql
  okd-lb
  okd-01
  okd-02
  okd-03
)

for binary in aws ssh; do
  command -v "$binary" >/dev/null 2>&1 || { echo "Required command not found: $binary" >&2; exit 1; }
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
    "$OPENSTACK_CLIENT" --os-cloud "$OPENSTACK_CLOUD" "$@"
  ssh "${SSH_OPTS[@]}" "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" "$remote_cmd"
}

printf 'Waiting for the OpenStack control plane on lab-host %s...\n' "$LAB_HOST_PRIVATE_IP"
openstack_ready=false
for attempt in $(seq 1 "$OPENSTACK_READY_ATTEMPTS"); do
  if remote_openstack token issue -f value -c id >/dev/null 2>&1; then
    openstack_ready=true
    break
  fi
  if (( attempt == 1 || attempt % 12 == 0 )); then
    printf '  OpenStack API not ready yet (%d/%d)...\n' "$attempt" "$OPENSTACK_READY_ATTEMPTS"
  fi
  sleep "$OPENSTACK_READY_INTERVAL_SECONDS"
done

if [[ "$openstack_ready" != true ]]; then
  echo "OpenStack did not become ready on lab-host within the recovery window." >&2
  exit 1
fi

for server in "${DESIRED_SERVERS[@]}"; do
  status=$(remote_openstack server show "$server" -f value -c status 2>/dev/null || true)
  case "$status" in
    ACTIVE)
      printf 'OpenStack guest %-22s already ACTIVE\n' "$server"
      ;;
    SHUTOFF)
      printf 'Starting OpenStack guest %-22s ...\n' "$server"
      remote_openstack server start "$server"
      ;;
    "")
      # Runtime OKD nodes do not exist during the first configure-lab run yet.
      printf 'OpenStack guest %-22s not created yet; skipping\n' "$server"
      ;;
    *)
      echo "OpenStack guest $server is in unexpected state '$status'; refusing to hide it." >&2
      exit 1
      ;;
  esac
done

for server in "${DESIRED_SERVERS[@]}"; do
  status=$(remote_openstack server show "$server" -f value -c status 2>/dev/null || true)
  [[ -z "$status" ]] && continue

  for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
    status=$(remote_openstack server show "$server" -f value -c status 2>/dev/null || true)
    [[ "$status" == "ACTIVE" ]] && break
    sleep "$WAIT_INTERVAL_SECONDS"
  done

  if [[ "$status" != "ACTIVE" ]]; then
    echo "OpenStack guest $server did not become ACTIVE (last state: ${status:-missing})." >&2
    exit 1
  fi
done

printf 'Known OpenStack platform guests are ACTIVE.\n'
