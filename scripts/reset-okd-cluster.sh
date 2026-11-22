#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME_ROOT=${OKD_RUNTIME_ROOT:-$ROOT_DIR/.runtime/openshift}
CONFIRM=${CONFIRM:-}

if [[ "$CONFIRM" != "RESET-OKD" ]]; then
  cat >&2 <<'EOF'
Refusing destructive OKD reset without explicit confirmation.

This removes:
  - bootstrap / okd-01 / okd-02 / okd-03 Nova runtime resources
  - their Neutron ports
  - all Kubernetes-managed Cinder PV/PVC volumes
  - integrated OpenShift registry storage
  - local OKD installer/auth/runtime assets

It preserves:
  - the OpenStack/Kolla control plane
  - Jenkins controller/worker
  - PostgreSQL VM and its external Cinder-backed data
  - okd-lb
  - edge-gateway

Run explicitly:
  CONFIRM=RESET-OKD make reset-okd-cluster
EOF
  exit 2
fi

printf '%s\n' '============================================================'
printf '%s\n' ' DESTRUCTIVE OKD CLUSTER RESET'
printf '%s\n' '============================================================'

# Destroy goes through cleanup-openshift-storage first while the API/CSI stack
# is still alive, then removes only the runtime OKD Terraform layer.
"$ROOT_DIR/scripts/okd-nodes.sh" destroy

printf '\nCleaning stale OKD installation/runtime identity...\n'
rm -rf   "$RUNTIME_ROOT/install"   "$RUNTIME_ROOT/ignition-stubs"   "$RUNTIME_ROOT/recovered"

rm -f   "$RUNTIME_ROOT/install-assets.ready"   "$RUNTIME_ROOT/existing-cluster.ready"   "$RUNTIME_ROOT/storage-foundation.ready"   "$RUNTIME_ROOT/terraform-nodes/recover-state.tfplan"   "$RUNTIME_ROOT/terraform-nodes/terraform.tfstate"   "$RUNTIME_ROOT/terraform-nodes/terraform.tfstate.backup"   "$RUNTIME_ROOT/terraform-nodes/runtime.auto.tfvars.json"

printf '\nValidating that no OKD runtime Nova machines remain...\n'
STATUS=$("$ROOT_DIR/scripts/okd-nodes.sh" status)
printf '%s\n' "$STATUS"

if awk '$1 ~ /^(bootstrap|okd-01|okd-02|okd-03)$/ && $2 != "MISSING" {bad=1} END {exit bad ? 0 : 1}' <<<"$STATUS"; then
  echo "OKD reset is incomplete: at least one runtime Nova machine still exists." >&2
  exit 1
fi

printf '\n%s\n' 'OKD CLUSTER RESET COMPLETE.'
printf '%s\n' 'Next: make configure-lab'
printf '%s\n' 'configure-lab will follow the fresh-install path and generate a new cluster identity.'
