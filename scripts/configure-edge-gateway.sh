#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
INVENTORY="$ANSIBLE_DIR/inventories/edge-gateway/hosts.yml"
AWS_REGION=${AWS_REGION:-eu-south-2}
EDGE_GATEWAY_PRIVATE_IP=${EDGE_GATEWAY_PRIVATE_IP:-172.31.31.71}
EDGE_SSH_KEY_PARAMETER=${EDGE_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
JENKINS_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
[[ -n "$JENKINS_FLOATING_IP" ]] || { echo "Usage: $0 <jenkins-floating-ip>" >&2; exit 2; }
python3 -c 'import ipaddress,sys; [ipaddress.IPv4Address(x) for x in sys.argv[1:]]' "$EDGE_GATEWAY_PRIVATE_IP" "$JENKINS_FLOATING_IP"
[[ -x "$ANSIBLE_PLAYBOOK" && -x "$ANSIBLE_BIN" ]] || { echo "Ansible missing on ops-runner" >&2; exit 1; }
EDGE_KEY=$(mktemp /tmp/private-banking-edge-key.XXXXXX)
trap 'rm -f "$EDGE_KEY"' EXIT
aws ssm get-parameter --region "$AWS_REGION" --name "$EDGE_SSH_KEY_PARAMETER" --with-decryption --query 'Parameter.Value' --output text > "$EDGE_KEY"
chmod 0600 "$EDGE_KEY"
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
EXTRA_VARS="edge_gateway_ansible_host=$EDGE_GATEWAY_PRIVATE_IP edge_gateway_ssh_private_key_file=$EDGE_KEY jenkins_floating_ip=$JENKINS_FLOATING_IP"
cd "$ANSIBLE_DIR"
printf '==> Checking edge-gateway connectivity (%s)\n' "$EDGE_GATEWAY_PRIVATE_IP"
"$ANSIBLE_BIN" -i "$INVENTORY" edge_gateways -m ansible.builtin.ping -e "$EXTRA_VARS"
printf '==> Configuring Nginx -> Jenkins (%s:8080)\n' "$JENKINS_FLOATING_IP"
"$ANSIBLE_PLAYBOOK" -i "$INVENTORY" playbooks/configure-edge-gateway.yml -e "$EXTRA_VARS"
