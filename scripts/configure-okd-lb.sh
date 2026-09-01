#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
INVENTORY="$ANSIBLE_DIR/inventories/okd-lb/hosts.yml"
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}
BOOTSTRAP_MODE=${2:-auto}
RUNTIME_TFVARS="$ROOT_DIR/.runtime/openshift/terraform-nodes/runtime.auto.tfvars.json"

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  echo "Usage: $0 <okd-lb-floating-ip> [auto|bootstrap|steady-state]" >&2
  echo "Example: $0 192.168.250.105 auto" >&2
  exit 2
fi

case "$BOOTSTRAP_MODE" in
  auto|bootstrap|steady-state) ;;
  *)
    echo "Unknown bootstrap mode: $BOOTSTRAP_MODE" >&2
    echo "Expected one of: auto, bootstrap, steady-state" >&2
    exit 2
    ;;
esac

python3 - "$OKD_LB_FLOATING_IP" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

for executable in "$ANSIBLE_PLAYBOOK" "$ANSIBLE_BIN"; do
  if [[ ! -x "$executable" ]]; then
    echo "Missing Ansible executable: $executable" >&2
    echo "Rebuild/bootstrap the ops-runner first." >&2
    exit 1
  fi
done

if [[ ! -r "$WORKLOAD_KEY" ]]; then
  echo "Missing workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

if [[ "$(stat -c '%a' "$WORKLOAD_KEY")" != "600" ]]; then
  echo "The workload SSH private key must have mode 0600: $WORKLOAD_KEY" >&2
  exit 1
fi

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

case "$BOOTSTRAP_MODE" in
  bootstrap)
    BOOTSTRAP_BACKENDS_ENABLED=true
    ;;
  steady-state)
    BOOTSTRAP_BACKENDS_ENABLED=false
    ;;
  auto)
    BOOTSTRAP_BACKENDS_ENABLED=true
    if [[ -s "$RUNTIME_TFVARS" ]] && command -v jq >/dev/null 2>&1; then
      if [[ "$(jq -r 'if has("bootstrap_enabled") then .bootstrap_enabled else true end' "$RUNTIME_TFVARS")" == false ]]; then
        BOOTSTRAP_BACKENDS_ENABLED=false
      fi
    fi
    ;;
esac

EXTRA_VARS="okd_lb_ansible_host=$OKD_LB_FLOATING_IP okd_bootstrap_backends_enabled=$BOOTSTRAP_BACKENDS_ENABLED"

cd "$ANSIBLE_DIR"

printf '==> SSH/Ansible connectivity check to okd-lb (%s)\n' "$OKD_LB_FLOATING_IP"
"$ANSIBLE_BIN" \
  -i "$INVENTORY" \
  okd_lbs \
  -m ansible.builtin.ping \
  -e "$EXTRA_VARS"

printf '==> Configuring OKD DNS, HAProxy and private Ignition HTTP endpoint (bootstrap_backends=%s)\n' "$BOOTSTRAP_BACKENDS_ENABLED"
"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  playbooks/configure-okd-lb.yml \
  -e "$EXTRA_VARS"
