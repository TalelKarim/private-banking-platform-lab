#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLEANUP_TIMEOUT_SECONDS=${CLEANUP_TIMEOUT_SECONDS:-300}
STORAGE_READY_MARKER=${STORAGE_READY_MARKER:-$ROOT_DIR/.runtime/openshift/storage-foundation.ready}
CINDER_DRIVER=cinder.csi.openstack.org

# Dynamic Cinder volumes are created by Kubernetes and are not in the runtime
# Terraform state. Delete them while the API + CSI controller are alive so the
# Cinder reclaim/finalizer path can finish before the OKD VMs disappear.
#
# The cleanup must cover *all* Cinder-backed PVCs, not only the integrated
# registry. Manual smoke-test PVCs and future application PVCs are dynamic
# Cinder volumes too and would otherwise block the destroy (or be orphaned if
# the safety check were bypassed).
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

if oc get csidriver "$CINDER_DRIVER" >/dev/null 2>&1; then
  storage_was_configured=true
fi

if [[ "$storage_was_configured" != true ]]; then
  echo "Cinder CSI is not installed; no OpenShift Cinder cleanup is required."
  exit 0
fi

list_cinder_pvs() {
  oc get pv -o json | python3 -c '
import json
import sys

driver = sys.argv[1]
data = json.load(sys.stdin)
for item in data.get("items", []):
    spec = item.get("spec", {})
    csi = spec.get("csi", {})
    if csi.get("driver") != driver:
        continue
    claim = spec.get("claimRef") or {}
    fields = (
        item.get("metadata", {}).get("name", ""),
        claim.get("namespace", ""),
        claim.get("name", ""),
        csi.get("volumeHandle", ""),
    )
    print("|".join(fields))
' "$CINDER_DRIVER"
}

list_pvc_consumers() {
  local namespace=$1
  local pvc=$2
  oc get pods -n "$namespace" -o json | python3 -c '
import json
import sys

claim = sys.argv[1]
data = json.load(sys.stdin)
for pod in data.get("items", []):
    uses_claim = any(
        (volume.get("persistentVolumeClaim") or {}).get("claimName") == claim
        for volume in pod.get("spec", {}).get("volumes", [])
    )
    if not uses_claim:
        continue
    owners = pod.get("metadata", {}).get("ownerReferences") or []
    owner = owners[0] if owners else {}
    print("|".join((
        pod.get("metadata", {}).get("name", ""),
        owner.get("kind", ""),
        owner.get("name", ""),
    )))
' "$pvc"
}

quiesce_pod_owner() {
  local namespace=$1
  local pod=$2
  local owner_kind=${3:-}
  local owner_name=${4:-}
  local parent_kind parent_name

  case "$owner_kind" in
    StatefulSet)
      printf '    scaling StatefulSet %s/%s to 0\n' "$namespace" "$owner_name"
      oc scale statefulset "$owner_name" -n "$namespace" --replicas=0 >/dev/null 2>&1 || true
      ;;
    ReplicaSet)
      parent_kind=$(oc get replicaset "$owner_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)
      parent_name=$(oc get replicaset "$owner_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || true)
      if [[ "$parent_kind" == "Deployment" && -n "$parent_name" ]]; then
        printf '    scaling Deployment %s/%s to 0\n' "$namespace" "$parent_name"
        oc scale deployment "$parent_name" -n "$namespace" --replicas=0 >/dev/null 2>&1 || true
      else
        printf '    scaling ReplicaSet %s/%s to 0\n' "$namespace" "$owner_name"
        oc scale replicaset "$owner_name" -n "$namespace" --replicas=0 >/dev/null 2>&1 || true
      fi
      ;;
    ReplicationController)
      printf '    scaling ReplicationController %s/%s to 0\n' "$namespace" "$owner_name"
      oc scale replicationcontroller "$owner_name" -n "$namespace" --replicas=0 >/dev/null 2>&1 || true
      ;;
    DaemonSet)
      # A DaemonSet cannot be scaled. The cluster is intentionally being
      # destroyed, so deleting the owner is safer than letting it recreate a
      # Pod that keeps the PVC protection finalizer alive.
      printf '    deleting DaemonSet %s/%s\n' "$namespace" "$owner_name"
      oc delete daemonset "$owner_name" -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      ;;
    Job)
      printf '    deleting Job %s/%s\n' "$namespace" "$owner_name"
      oc delete job "$owner_name" -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      ;;
  esac

  # Standalone Pods (such as the phase1-cinder-test smoke Pod) have no owner.
  # Managed Pods are also deleted after their owner is quiesced so PVC
  # protection can release promptly and Cinder can detach the volume.
  printf '    deleting consumer Pod %s/%s\n' "$namespace" "$pod"
  oc delete pod "$pod" -n "$namespace" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

printf '==> Stopping the integrated image registry before reclaiming Cinder PVCs\n'
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge \
  -p '{"spec":{"managementState":"Removed"}}' >/dev/null 2>&1 || true

for _ in $(seq 1 90); do
  replicas=$(oc get deployment/image-registry -n openshift-image-registry -o jsonpath='{.status.replicas}' 2>/dev/null || true)
  [[ -z "$replicas" || "$replicas" == "0" ]] && break
  sleep 2
done

mapfile -t cinder_rows < <(list_cinder_pvs)

if [[ ${#cinder_rows[@]} -eq 0 ]]; then
  printf '==> No Cinder-backed PVs remain; skipping PVC reclamation\n'
else
  printf '==> Quiescing consumers of every Cinder-backed PVC before deletion\n'
  for row in "${cinder_rows[@]}"; do
    IFS='|' read -r pv namespace pvc volume_handle <<<"$row"
    if [[ -z "$namespace" || -z "$pvc" ]]; then
      printf '  - PV %s has no active claimRef (volume %s); waiting for CSI reclaim\n' "$pv" "${volume_handle:-unknown}"
      continue
    fi

    printf '  - %s/%s -> %s (Cinder %s)\n' "$namespace" "$pvc" "$pv" "${volume_handle:-unknown}"
    mapfile -t consumers < <(list_pvc_consumers "$namespace" "$pvc")
    for consumer in "${consumers[@]}"; do
      IFS='|' read -r pod owner_kind owner_name <<<"$consumer"
      quiesce_pod_owner "$namespace" "$pod" "$owner_kind" "$owner_name"
    done
  done

  printf '==> Deleting every Cinder-backed PVC while CSI is still alive\n'
  for row in "${cinder_rows[@]}"; do
    IFS='|' read -r _pv namespace pvc _volume_handle <<<"$row"
    [[ -n "$namespace" && -n "$pvc" ]] || continue
    oc delete pvc "$pvc" -n "$namespace" --ignore-not-found --wait=false >/dev/null
  done
fi

cinder_rows=()
deadline=$((SECONDS + CLEANUP_TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  mapfile -t cinder_rows < <(list_cinder_pvs)
  [[ ${#cinder_rows[@]} -eq 0 ]] && break
  sleep 3
done

if [[ ${#cinder_rows[@]} -ne 0 ]]; then
  echo "Cinder PVs still exist after cleanup timeout:" >&2
  for row in "${cinder_rows[@]}"; do
    IFS='|' read -r pv namespace pvc volume_handle <<<"$row"
    printf '  - PV=%s claim=%s/%s volume=%s\n' \
      "$pv" "${namespace:--}" "${pvc:--}" "${volume_handle:--}" >&2
    if [[ -n "$namespace" && -n "$pvc" ]]; then
      mapfile -t consumers < <(list_pvc_consumers "$namespace" "$pvc")
      for consumer in "${consumers[@]}"; do
        IFS='|' read -r pod owner_kind owner_name <<<"$consumer"
        printf '      consumer pod=%s owner=%s/%s\n' \
          "$pod" "${owner_kind:-none}" "${owner_name:-none}" >&2
      done
    fi
  done
  echo "Refusing to destroy the OKD nodes and risk orphaning volumes." >&2
  exit 1
fi

printf '==> Removing Cinder CSI runtime objects after all dynamic volumes are gone\n'
if command -v helm >/dev/null 2>&1; then
  helm uninstall cinder-csi -n kube-system >/dev/null 2>&1 || true
fi
oc delete storageclass cinder-standard --ignore-not-found >/dev/null
oc delete -f "$ROOT_DIR/platform/openshift/storage/cinder-csi-scc.yaml" --ignore-not-found >/dev/null 2>&1 || true
oc delete secret cinder-csi-cloud-config -n kube-system --ignore-not-found >/dev/null
rm -f "$STORAGE_READY_MARKER"

printf 'OpenShift Cinder/registry cleanup COMPLETE.\n'
