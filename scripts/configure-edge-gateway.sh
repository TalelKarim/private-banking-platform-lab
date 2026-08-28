#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
INVENTORY="$ANSIBLE_DIR/inventories/edge-gateway/hosts.yml"
AWS_REGION=${AWS_REGION:-eu-south-2}
EDGE_GATEWAY_PRIVATE_IP=${EDGE_GATEWAY_PRIVATE_IP:-172.31.31.71}
OPENSTACK_HORIZON_BACKEND_HOST=${OPENSTACK_HORIZON_BACKEND_HOST:-172.31.31.70}
EDGE_SSH_KEY_PARAMETER=${EDGE_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
JENKINS_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
OKD_LB_FLOATING_IP=${2:-${OKD_LB_FLOATING_IP:-}}

[[ -n "$JENKINS_FLOATING_IP" && -n "$OKD_LB_FLOATING_IP" ]] || {
  echo "Usage: $0 <jenkins-floating-ip> <okd-lb-floating-ip>" >&2
  exit 2
}

python3 -c 'import ipaddress,sys; [ipaddress.IPv4Address(x) for x in sys.argv[1:]]' \
  "$EDGE_GATEWAY_PRIVATE_IP" "$OPENSTACK_HORIZON_BACKEND_HOST" \
  "$JENKINS_FLOATING_IP" "$OKD_LB_FLOATING_IP"

[[ -x "$ANSIBLE_PLAYBOOK" && -x "$ANSIBLE_BIN" && -x "$ANSIBLE_PYTHON" ]] || {
  echo "Ansible control environment missing on ops-runner" >&2
  exit 1
}

read -r EDGE_LAB_BASE_DOMAIN EDGE_OKD_CLUSTER_NAME < <(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
print(cfg['okd_base_domain'], cfg['okd_cluster_name'])
PY
)

EDGE_KEY=$(mktemp /tmp/private-banking-edge-key.XXXXXX)
trap 'rm -f "$EDGE_KEY"' EXIT
aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$EDGE_SSH_KEY_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$EDGE_KEY"
chmod 0600 "$EDGE_KEY"

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
EXTRA_VARS="edge_gateway_ansible_host=$EDGE_GATEWAY_PRIVATE_IP edge_gateway_ssh_private_key_file=$EDGE_KEY jenkins_floating_ip=$JENKINS_FLOATING_IP okd_lb_floating_ip=$OKD_LB_FLOATING_IP openstack_horizon_backend_host=$OPENSTACK_HORIZON_BACKEND_HOST edge_lab_base_domain=$EDGE_LAB_BASE_DOMAIN edge_okd_cluster_name=$EDGE_OKD_CLUSTER_NAME"

cd "$ANSIBLE_DIR"
printf '==> Checking edge-gateway connectivity (%s)\n' "$EDGE_GATEWAY_PRIVATE_IP"
"$ANSIBLE_BIN" -i "$INVENTORY" edge_gateways -m ansible.builtin.ping -e "$EXTRA_VARS"

printf '==> Configuring public lab reverse proxy\n'
printf '    Jenkins : jenkins.%s -> %s:8080\n' "$EDGE_LAB_BASE_DOMAIN" "$JENKINS_FLOATING_IP"
printf '    Horizon : cloud.%s -> %s:80\n' "$EDGE_LAB_BASE_DOMAIN" "$OPENSTACK_HORIZON_BACKEND_HOST"
printf '    OKD apps: *.apps.%s.%s -> %s:443\n' "$EDGE_OKD_CLUSTER_NAME" "$EDGE_LAB_BASE_DOMAIN" "$OKD_LB_FLOATING_IP"
"$ANSIBLE_PLAYBOOK" -i "$INVENTORY" playbooks/configure-edge-gateway.yml -e "$EXTRA_VARS"
