#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLEANUP_TIMEOUT_SECONDS=${CLEANUP_TIMEOUT_SECONDS:-300}
STORAGE_READY_MARKER=${STORAGE_READY_MARKER:-$ROOT_DIR/.runtime/openshift/storage-foundation.ready}

# Dynamic Cinder volumes are created by Kubernetes and are not in the runtime
# Terraform state. Delete them while the API + CSI controller are alive so the
# Cinder reclaim/finalizer path can finish before the OKD VMs disappear.
#
# A successful storage convergence leaves a runtime marker. If the marker is
# missing we still detect CSI through the live API when possible; this keeps a
# failed OKD install (where CSI was never installed) destroyable without an
# unsafe blanket bypass.
storage_was_configured=false
[[ -f "$STORAGE_READY_MARKER" ]] && storage_was_configured=true

if [[ ! -r "$KUBECONFIG" ]] || ! command -v oc >/dev/null 2>&1; then
  if [[ "$storage_was_configured" == true ]]; then
    echo "Storage was configured but OKD kubeconfig/oc is unavailable; refusing unsafe destroy." >&2
    echo "Emergency bypass only: SKIP_OPENSHIFT_STORAGE_CLEANUP=true make destroy-okd-nodes" >&2
    exit 1
  fi
  echo "No storage-ready marker and no usable OKD client; nothing CSI-managed is known locally."
  exit 0
fi
export KUBECONFIG

if ! oc get --raw=/readyz >/dev/null 2>&1; then
  if [[ "$storage_was_configured" == true ]]; then
    echo "OKD API is unreachable; refusing to destroy OKD nodes while dynamic Cinder storage may exist." >&2
    echo "Recover the cluster first (make recover-openstack-guests), then retry the destroy." >&2
    echo "Emergency bypass only: SKIP_OPENSHIFT_STORAGE_CLEANUP=true make destroy-okd-nodes" >&2
    exit 1
  fi
  echo "OKD API is unreachable and storage was never marked ready; skipping CSI cleanup."
  exit 0
fi

if oc get csidriver cinder.csi.openstack.org >/dev/null 2>&1; then
  storage_was_configured=true
fi

if [[ "$storage_was_configured" != true ]]; then
  echo "Cinder CSI is not installed; no OpenShift Cinder cleanup is required."
  exit 0
fi

printf '==> Stopping the integrated image registry before deleting its RWO PVC\n'
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge \
  -p '{"spec":{"managementState":"Removed"}}' >/dev/null 2>&1 || true

for _ in $(seq 1 90); do
  replicas=$(oc get deployment/image-registry -n openshift-image-registry -o jsonpath='{.status.replicas}' 2>/dev/null || true)
  [[ -z "$replicas" || "$replicas" == "0" ]] && break
  sleep 2
done

printf '==> Deleting registry PVC and waiting for Cinder reclaimPolicy=Delete\n'
oc delete pvc image-registry-storage -n openshift-image-registry --ignore-not-found --wait=false >/dev/null

cinder_pvs=()
deadline=$((SECONDS + CLEANUP_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  mapfile -t cinder_pvs < <(oc get pv -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(x["metadata"]["name"]) for x in d.get("items",[]) if x.get("spec",{}).get("csi",{}).get("driver")=="cinder.csi.openstack.org"]')
  [[ ${#cinder_pvs[@]} -eq 0 ]] && break
  sleep 3
done

if [[ ${#cinder_pvs[@]} -ne 0 ]]; then
  echo "Cinder PVs still exist after cleanup timeout: ${cinder_pvs[*]}" >&2
  echo "Refusing to destroy the OKD nodes and risk orphaning volumes." >&2
  exit 1
fi

printf '==> Removing Cinder CSI runtime objects after volumes are gone\n'
if command -v helm >/dev/null 2>&1; then
  helm uninstall cinder-csi -n kube-system >/dev/null 2>&1 || true
fi
oc delete storageclass cinder-standard --ignore-not-found >/dev/null
oc delete -f "$ROOT_DIR/platform/openshift/storage/cinder-csi-scc.yaml" --ignore-not-found >/dev/null 2>&1 || true
oc delete secret cinder-csi-cloud-config -n kube-system --ignore-not-found >/dev/null
rm -f "$STORAGE_READY_MARKER"

printf 'OpenShift Cinder/registry cleanup COMPLETE.\n'
