#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
RUNTIME_ROOT=${OKD_RUNTIME_ROOT:-$ROOT_DIR/.runtime/openshift}
INSTALL_DIR="$RUNTIME_ROOT/install"
KUBECONFIG_PATH="$INSTALL_DIR/auth/kubeconfig"
TF_VARS="$RUNTIME_ROOT/terraform-nodes/runtime.auto.tfvars.json"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
OKD_LB_SERVER_NAME=${OKD_LB_SERVER_NAME:-okd-lb}
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}

for binary in openshift-install oc jq getent; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

if [[ ! -x "$ANSIBLE_PYTHON" ]]; then
  echo "Python from the Ansible control environment is required: $ANSIBLE_PYTHON" >&2
  exit 1
fi

for required in \
  "$INSTALL_DIR/metadata.json" \
  "$KUBECONFIG_PATH"; do
  [[ -s "$required" ]] || {
    echo "Missing OKD installer runtime asset: $required" >&2
    echo "Run make prepare-okd-install-assets before completing the installation." >&2
    exit 1
  }
done

read -r OKD_CLUSTER_NAME OKD_BASE_DOMAIN < <(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = yaml.safe_load(handle)
print(cfg["okd_cluster_name"], cfg["okd_base_domain"])
PY
)
API_FQDN="api.${OKD_CLUSTER_NAME}.${OKD_BASE_DOMAIN}"

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
fi

python3 - "$OKD_LB_FLOATING_IP" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

resolved_api=$(getent ahostsv4 "$API_FQDN" | awk 'NR == 1 {print $1}')
if [[ "$resolved_api" != "$OKD_LB_FLOATING_IP" ]]; then
  echo "ops-runner API resolution is not ready: $API_FQDN -> ${resolved_api:-none}" >&2
  echo "Expected the okd-lb floating IP: $OKD_LB_FLOATING_IP" >&2
  echo "Run: make configure-okd-client-access OKD_LB_FLOATING_IP=$OKD_LB_FLOATING_IP" >&2
  exit 1
fi


printf '%s\n' '============================================================'
printf '%s\n' ' OKD installation completion + bootstrap retirement'
printf '%s\n' '============================================================'
printf '%-24s %s\n' 'Cluster' "$OKD_CLUSTER_NAME.$OKD_BASE_DOMAIN"
printf '%-24s %s\n' 'API' "https://$API_FQDN:6443"
printf '%-24s %s\n' 'Installer assets' "$INSTALL_DIR"

printf '\n[1/5] Waiting for openshift-install bootstrap-complete...\n'
# This is the safety gate. Bootstrap is never removed merely because Nova says
# the control planes are ACTIVE; only the installer can declare it disposable.
openshift-install wait-for bootstrap-complete \
  --dir "$INSTALL_DIR" \
  --log-level=info

printf '\n[2/5] Removing bootstrap from OKD DNS/HAProxy backends...\n'
"$ROOT_DIR/scripts/configure-okd-lb.sh" "$OKD_LB_FLOATING_IP" steady-state

printf '\n[3/5] Destroying only the temporary bootstrap VM and Neutron port...\n'
"$ROOT_DIR/scripts/okd-nodes.sh" retire-bootstrap

if [[ -s "$TF_VARS" ]]; then
  bootstrap_enabled=$(jq -r '.bootstrap_enabled // true' "$TF_VARS")
  if [[ "$bootstrap_enabled" != false ]]; then
    echo "Runtime Terraform still reports bootstrap_enabled=$bootstrap_enabled" >&2
    exit 1
  fi
fi

printf '\n[4/5] Waiting for openshift-install install-complete...\n'
openshift-install wait-for install-complete \
  --dir "$INSTALL_DIR" \
  --log-level=info

printf '\n[5/5] Validating the compact three-node cluster...\n'
export KUBECONFIG="$KUBECONFIG_PATH"
NODE_JSON=$(oc get nodes -o json)
NODE_COUNT=$(jq '.items | length' <<<"$NODE_JSON")
NOT_READY=$(
  jq -r '
    .items[]
    | select(any(.status.conditions[]?; .type == "Ready" and .status == "True") | not)
    | .metadata.name
  ' <<<"$NODE_JSON"
)

if [[ "$NODE_COUNT" -ne 3 ]]; then
  echo "Expected exactly three compact OKD nodes, found $NODE_COUNT." >&2
  oc get nodes -o wide >&2 || true
  exit 1
fi

if [[ -n "$NOT_READY" ]]; then
  echo "The following OKD nodes are not Ready:" >&2
  printf '%s\n' "$NOT_READY" >&2
  oc get nodes -o wide >&2 || true
  exit 1
fi

oc get nodes -o wide
printf '\nCluster operators summary:\n'
oc get clusteroperators

printf '\n%s\n' '------------------------------------------------------------'
printf '%-28s %s\n' 'bootstrap-complete' 'YES'
printf '%-28s %s\n' 'Bootstrap HAProxy/DNS' 'REMOVED'
printf '%-28s %s\n' 'Bootstrap Nova VM/port' 'REMOVED'
printf '%-28s %s\n' 'install-complete' 'YES'
printf '%-28s %s\n' 'Compact nodes Ready' '3/3'
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'OKD INSTALLATION COMPLETE - BOOTSTRAP RETIRED'
