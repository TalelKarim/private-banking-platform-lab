#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
INVENTORY="$ANSIBLE_DIR/inventories/okd-lb/hosts.yml"
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  echo "Usage: $0 <okd-lb-floating-ip>" >&2
  echo "Example: $0 192.168.250.105" >&2
  exit 2
fi

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
EXTRA_VARS="okd_lb_ansible_host=$OKD_LB_FLOATING_IP"

cd "$ANSIBLE_DIR"

printf '==> SSH/Ansible connectivity check to okd-lb (%s)\n' "$OKD_LB_FLOATING_IP"
"$ANSIBLE_BIN" \
  -i "$INVENTORY" \
  okd_lbs \
  -m ansible.builtin.ping \
  -e "$EXTRA_VARS"

printf '==> Configuring OKD DNS, HAProxy and private Ignition HTTP endpoint\n'
"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  playbooks/configure-okd-lb.yml \
  -e "$EXTRA_VARS"
