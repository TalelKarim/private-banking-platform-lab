#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
RUNTIME_ROOT=${OKD_RUNTIME_ROOT:-$ROOT_DIR/.runtime/openshift}
INSTALL_DIR="$RUNTIME_ROOT/install"
READY_FILE="$RUNTIME_ROOT/install-assets.ready"
WORKLOAD_KEY=${WORKLOAD_SSH_PRIVATE_KEY:-/home/ubuntu/.ssh/private-banking-openstack-workloads}
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}
REMOTE_IGNITION_ROOT=${REMOTE_IGNITION_ROOT:-/srv/okd/ignition}

read_config_value() {
  local key=$1
  awk -F': *' -v wanted="$key" '$1 == wanted {print $2; exit}' "$CLUSTER_CONFIG"
}

OKD_LB_IP=$(read_config_value okd_lb_ip)
OKD_IGNITION_HTTP_PORT=$(read_config_value okd_ignition_http_port)

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  echo "Usage: $0 <okd-lb-floating-ip>" >&2
  exit 2
fi

python3 - "$OKD_LB_FLOATING_IP" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

for required in "$READY_FILE" "$INSTALL_DIR/bootstrap.ign" "$INSTALL_DIR/master.ign" "$INSTALL_DIR/ignition.sha256"; do
  [[ -s "$required" ]] || {
    echo "Missing generated OKD asset: $required" >&2
    echo "Run make generate-okd-install-assets first." >&2
    exit 1
  }
done

if [[ ! -r "$WORKLOAD_KEY" ]]; then
  echo "Missing workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

SSH_OPTS=(
  -i "$WORKLOAD_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)
REMOTE="ubuntu@$OKD_LB_FLOATING_IP"

printf 'Preparing private Ignition document root on okd-lb...\n'
ssh "${SSH_OPTS[@]}" "$REMOTE" \
  "sudo install -d -m 0750 -o root -g www-data '$REMOTE_IGNITION_ROOT' && sudo rm -f '$REMOTE_IGNITION_ROOT'/*.ign '$REMOTE_IGNITION_ROOT'/ignition.sha256"

publish_file() {
  local source=$1
  local destination=$2
  cat "$source" | ssh "${SSH_OPTS[@]}" "$REMOTE" \
    "sudo tee '$destination' >/dev/null && sudo chown root:www-data '$destination' && sudo chmod 0640 '$destination'"
}

printf 'Publishing bootstrap.ign...\n'
publish_file "$INSTALL_DIR/bootstrap.ign" "$REMOTE_IGNITION_ROOT/bootstrap.ign"
printf 'Publishing master.ign...\n'
publish_file "$INSTALL_DIR/master.ign" "$REMOTE_IGNITION_ROOT/master.ign"
printf 'Publishing SHA-256 manifest...\n'
publish_file "$INSTALL_DIR/ignition.sha256" "$REMOTE_IGNITION_ROOT/ignition.sha256"

printf 'Validating files on okd-lb...\n'
# The Ignition directory is deliberately root:www-data mode 0750 so the
# unprivileged SSH user (ubuntu) cannot cd into it. Enter the directory inside
# the privileged shell, then verify the relative filenames from the manifest.
ssh "${SSH_OPTS[@]}" "$REMOTE" \
  "sudo sh -c 'cd \"$REMOTE_IGNITION_ROOT\" && sha256sum -c ignition.sha256'"

local_bootstrap_sha=$(sha256sum "$INSTALL_DIR/bootstrap.ign" | awk '{print $1}')
local_master_sha=$(sha256sum "$INSTALL_DIR/master.ign" | awk '{print $1}')

remote_bootstrap_sha=$(ssh "${SSH_OPTS[@]}" "$REMOTE" \
  "curl -fsS 'http://$OKD_LB_IP:$OKD_IGNITION_HTTP_PORT/bootstrap.ign' | sha256sum | cut -d ' ' -f1")
remote_master_sha=$(ssh "${SSH_OPTS[@]}" "$REMOTE" \
  "curl -fsS 'http://$OKD_LB_IP:$OKD_IGNITION_HTTP_PORT/master.ign' | sha256sum | cut -d ' ' -f1")

if [[ "$remote_bootstrap_sha" != "$local_bootstrap_sha" ]]; then
  echo "bootstrap.ign served by Nginx does not match the generated file." >&2
  exit 1
fi
if [[ "$remote_master_sha" != "$local_master_sha" ]]; then
  echo "master.ign served by Nginx does not match the generated file." >&2
  exit 1
fi

printf '\nRuntime Ignition publication is ready:\n'
printf '  bootstrap: http://%s:%s/bootstrap.ign\n' "$OKD_LB_IP" "$OKD_IGNITION_HTTP_PORT"
printf '  master:    http://%s:%s/master.ign\n' "$OKD_LB_IP" "$OKD_IGNITION_HTTP_PORT"
printf '  exposure:  private lab network only; files are not stored in Git or Terraform state\n'
