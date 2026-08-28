#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
INVENTORY="$ANSIBLE_DIR/inventories/lab-host-runtime/hosts.yml"
AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}

for binary in aws "$ANSIBLE_PLAYBOOK"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done

SSH_KEY=$(mktemp /tmp/private-banking-lab-host-key.XXXXXX)
trap 'rm -f "$SSH_KEY"' EXIT

aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$LAB_SSH_KEY_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$SSH_KEY"
chmod 0600 "$SSH_KEY"

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
cd "$ANSIBLE_DIR"

"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  playbooks/configure-openstack-runtime.yml \
  -e "lab_host_ansible_host=$LAB_HOST_PRIVATE_IP" \
  -e "lab_host_ssh_private_key_file=$SSH_KEY"
