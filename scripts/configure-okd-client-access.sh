#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
WORKLOAD_KEY=${WORKLOAD_SSH_PRIVATE_KEY:-/home/ubuntu/.ssh/private-banking-openstack-workloads}
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}

[[ -n "$OKD_LB_FLOATING_IP" ]] || { echo "Usage: $0 <okd-lb-floating-ip>" >&2; exit 2; }
[[ -x "$ANSIBLE_PYTHON" ]] || { echo "Missing Python: $ANSIBLE_PYTHON" >&2; exit 1; }
[[ -r "$WORKLOAD_KEY" ]] || { echo "Missing workload SSH key: $WORKLOAD_KEY" >&2; exit 1; }

python3 - "$OKD_LB_FLOATING_IP" <<'PY'
import ipaddress, sys
ipaddress.IPv4Address(sys.argv[1])
PY

CONFIG_JSON=$(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import json, sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
print(json.dumps(cfg))
PY
)

CLUSTER_NAME=$(jq -r '.okd_cluster_name' <<<"$CONFIG_JSON")
BASE_DOMAIN=$(jq -r '.okd_base_domain' <<<"$CONFIG_JSON")
API_FQDN="api.${CLUSTER_NAME}.${BASE_DOMAIN}"
API_INT_FQDN="api-int.${CLUSTER_NAME}.${BASE_DOMAIN}"
BOOTSTRAP_NAME=$(jq -r '.okd_bootstrap.name' <<<"$CONFIG_JSON")
BOOTSTRAP_IP=$(jq -r '.okd_bootstrap.ip' <<<"$CONFIG_JSON")

printf 'Configuring ops-runner split-horizon API resolution...\n'
sudo python3 - "$OKD_LB_FLOATING_IP" "$API_FQDN" "$API_INT_FQDN" <<'PY'
from pathlib import Path
import sys
ip, api, api_int = sys.argv[1:]
path = Path('/etc/hosts')
start = '# BEGIN private-banking-okd-client'
end = '# END private-banking-okd-client'
text = path.read_text()
lines = text.splitlines()
out = []
skip = False
for line in lines:
    if line.strip() == start:
        skip = True
        continue
    if line.strip() == end:
        skip = False
        continue
    if not skip:
        out.append(line)
out += [start, f'{ip} {api} {api_int}', end]
path.write_text('\n'.join(out) + '\n')
PY

resolved=$(getent ahostsv4 "$API_FQDN" | awk 'NR==1 {print $1}')
if [[ "$resolved" != "$OKD_LB_FLOATING_IP" ]]; then
  echo "ops-runner resolution mismatch: $API_FQDN -> ${resolved:-none}, expected $OKD_LB_FLOATING_IP" >&2
  exit 1
fi

printf 'Generating SSH aliases for okd-lb/bootstrap/control planes...\n'
mkdir -p "$HOME/.ssh/config.d"
chmod 0700 "$HOME/.ssh" "$HOME/.ssh/config.d"

SSH_FRAGMENT="$HOME/.ssh/config.d/private-banking-okd.conf"
{
  cat <<EOF_FRAGMENT
Host okd-lb
  HostName $OKD_LB_FLOATING_IP
  User ubuntu
  IdentityFile $WORKLOAD_KEY
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30

Host $BOOTSTRAP_NAME
  HostName $BOOTSTRAP_IP
  User core
  IdentityFile $WORKLOAD_KEY
  IdentitiesOnly yes
  ProxyJump okd-lb
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30

EOF_FRAGMENT

  while IFS=$'\t' read -r name ip; do
    cat <<EOF_FRAGMENT
Host $name $name.$CLUSTER_NAME.$BASE_DOMAIN
  HostName $ip
  User core
  IdentityFile $WORKLOAD_KEY
  IdentitiesOnly yes
  ProxyJump okd-lb
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30

EOF_FRAGMENT
  done < <(jq -r '.okd_control_planes[] | [.name, .ip] | @tsv' <<<"$CONFIG_JSON")
} > "$SSH_FRAGMENT"
chmod 0600 "$SSH_FRAGMENT"

SSH_CONFIG="$HOME/.ssh/config"
touch "$SSH_CONFIG"
chmod 0600 "$SSH_CONFIG"
INCLUDE_LINE='Include ~/.ssh/config.d/*.conf'
if ! grep -qxF "$INCLUDE_LINE" "$SSH_CONFIG"; then
  tmp=$(mktemp)
  {
    printf '%s\n\n' "$INCLUDE_LINE"
    cat "$SSH_CONFIG"
  } > "$tmp"
  mv "$tmp" "$SSH_CONFIG"
  chmod 0600 "$SSH_CONFIG"
fi

printf 'Validating SSH jump-host authentication...\n'
ssh okd-lb true

printf 'Validating routed DNS and OKD API listener reachability through the floating IP...\n'
if command -v dig >/dev/null 2>&1; then
  dns_answer=$(dig +time=3 +tries=1 +short "@$OKD_LB_FLOATING_IP" "$API_FQDN" | tail -n1)
  [[ -n "$dns_answer" ]] || { echo "No DNS response from okd-lb floating IP." >&2; exit 1; }
  printf '  authoritative lab DNS: %s -> %s\n' "$API_FQDN" "$dns_answer"
fi

timeout 5 bash -c "</dev/tcp/$OKD_LB_FLOATING_IP/6443" || {
  echo "TCP/6443 cannot traverse ops-runner -> lab-host -> okd-lb floating IP." >&2
  echo "Apply the AWS/OpenStack Terraform security changes, then rerun this command." >&2
  exit 1
}

printf '\nOKD client access READY on ops-runner:\n'
printf '  %-18s %s\n' 'API resolution' "$API_FQDN -> $OKD_LB_FLOATING_IP"
printf '  %-18s %s\n' 'Jump host' 'ssh okd-lb'
printf '  %-18s %s\n' 'Bootstrap SSH' "ssh $BOOTSTRAP_NAME"
printf '  %-18s %s\n' 'Node SSH' 'ssh okd-01 | ssh okd-02 | ssh okd-03'
