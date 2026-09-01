#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}

[[ -x "$ANSIBLE_PYTHON" ]] || { echo "Missing Python: $ANSIBLE_PYTHON" >&2; exit 1; }
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
command -v oc >/dev/null 2>&1 || { echo "Missing command: oc" >&2; exit 1; }
export KUBECONFIG

read -r STORAGE_CLASS REGISTRY_STORAGE_SIZE < <(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    cfg = yaml.safe_load(f)
print(cfg['okd_cinder_storage_class'], cfg['okd_registry_storage_size'])
PY
)

printf '==> Preflight: validating Cinder CSI before configuring the registry\n'
oc get csidriver cinder.csi.openstack.org >/dev/null
[[ "$(oc get storageclass "$STORAGE_CLASS" -o jsonpath='{.provisioner}')" == "cinder.csi.openstack.org" ]] || {
  echo "StorageClass $STORAGE_CLASS is not backed by cinder.csi.openstack.org." >&2
  exit 1
}

PVC_MANIFEST=$(mktemp /tmp/private-banking-registry-pvc.XXXXXX.yaml)
trap 'rm -f "$PVC_MANIFEST"' EXIT

"$ANSIBLE_PYTHON" - "$ROOT_DIR/platform/openshift/image-registry/pvc.yaml" "$PVC_MANIFEST" "$REGISTRY_STORAGE_SIZE" "$STORAGE_CLASS" <<'PY'
import sys, yaml
src, dst, size, storage_class = sys.argv[1:]
with open(src, encoding='utf-8') as f:
    doc = yaml.safe_load(f)
doc['spec']['storageClassName'] = storage_class
doc['spec']['resources']['requests']['storage'] = size
with open(dst, 'w', encoding='utf-8') as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY

printf '==> Creating/updating the registry PVC\n'
oc apply -f "$PVC_MANIFEST"

printf '==> Converging the integrated registry onto single-replica Cinder block storage\n'
# Cinder provides RWO block storage in this lab. OpenShift supports this for a
# single registry replica when the rollout strategy is Recreate. Keep
# defaultRoute=false in phase 1: phase 2 will create the Jenkins-only registry
# access path and explicitly prevent the public AWS edge from exposing it.
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p "$(cat <<'JSON'
{
  "spec": {
    "managementState": "Managed",
    "replicas": 1,
    "rolloutStrategy": "Recreate",
    "defaultRoute": false,
    "storage": {
      "pvc": {
        "claim": "image-registry-storage"
      }
    }
  }
}
JSON
)"

printf '==> Waiting for PVC binding and registry rollout\n'
phase=""
for _ in $(seq 1 180); do
  phase=$(oc get pvc image-registry-storage -n openshift-image-registry -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$phase" == "Bound" ]] && break
  sleep 2
done
if [[ "$phase" != "Bound" ]]; then
  echo "Registry PVC did not become Bound." >&2
  oc describe pvc image-registry-storage -n openshift-image-registry >&2 || true
  oc get events -n openshift-image-registry --sort-by=.lastTimestamp >&2 || true
  exit 1
fi

oc rollout status deployment/image-registry -n openshift-image-registry --timeout=10m
oc wait --for=condition=Available clusteroperator/image-registry --timeout=10m >/dev/null
oc wait --for=condition=Degraded=False clusteroperator/image-registry --timeout=10m >/dev/null

printf '\nOpenShift integrated registry storage READY:\n'
printf '  %-24s %s\n' 'PVC' "image-registry-storage ($REGISTRY_STORAGE_SIZE)"
printf '  %-24s %s\n' 'StorageClass' "$STORAGE_CLASS"
printf '  %-24s %s\n' 'Replica strategy' '1 replica / Recreate (RWO block storage)'
printf '  %-24s %s\n' 'External registry Route' 'DISABLED (phase 2)'
