#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
INVENTORY="$ANSIBLE_DIR/inventories/workloads/hosts.yml"
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
JENKINS_CONTROLLER_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
JENKINS_WORKER_FLOATING_IP=${2:-${JENKINS_WORKER_FLOATING_IP:-}}
JENKINS_WORKER_NAME=${JENKINS_WORKER_NAME:-jenkins-agent-01}

if [[ -z "$JENKINS_CONTROLLER_FLOATING_IP" || -z "$JENKINS_WORKER_FLOATING_IP" ]]; then
  echo "Usage: $0 <jenkins-controller-floating-ip> <jenkins-worker-floating-ip>" >&2
  echo "Example: $0 192.168.250.102 192.168.250.103" >&2
  exit 2
fi

python3 - "$JENKINS_CONTROLLER_FLOATING_IP" "$JENKINS_WORKER_FLOATING_IP" <<'PY'
import ipaddress
import sys
for value in sys.argv[1:]:
    ipaddress.IPv4Address(value)
PY

if [[ ! -x "$ANSIBLE_PLAYBOOK" || ! -x "$ANSIBLE_BIN" ]]; then
  echo "Ansible is not installed in /opt/ansible-venv. Rebuild/bootstrap the ops-runner first." >&2
  exit 1
fi

if [[ ! -r "$WORKLOAD_KEY" ]]; then
  echo "Missing workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

if [[ "$(stat -c '%a' "$WORKLOAD_KEY")" != "600" ]]; then
  echo "The workload SSH private key must have mode 0600: $WORKLOAD_KEY" >&2
  exit 1
fi

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
EXTRA_VARS="jenkins_controller_ansible_host=$JENKINS_CONTROLLER_FLOATING_IP jenkins_worker_ansible_host=$JENKINS_WORKER_FLOATING_IP jenkins_agent_node_name=$JENKINS_WORKER_NAME"

cd "$ANSIBLE_DIR"

printf '==> SSH/Ansible connectivity check to Jenkins controller (%s) and worker (%s)\n' \
  "$JENKINS_CONTROLLER_FLOATING_IP" "$JENKINS_WORKER_FLOATING_IP"
"$ANSIBLE_BIN" \
  -i "$INVENTORY" \
  'jenkins_controllers:jenkins_workers' \
  -m ansible.builtin.ping \
  -e "$EXTRA_VARS"

printf '==> Registering and configuring Jenkins worker %s\n' "$JENKINS_WORKER_NAME"
"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  playbooks/configure-jenkins-worker.yml \
  -e "$EXTRA_VARS"
