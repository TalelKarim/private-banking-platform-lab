#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
DEMO_NAMESPACE=${DEMO_NAMESPACE:-demo}
HELM_RELEASE=${HELM_RELEASE:-demo-3tier}
HELM_CHART_DIR=${HELM_CHART_DIR:-$ROOT_DIR/applications/demo-3tier/helm/demo-3tier}
FRONTEND_IMAGE_REF=${FRONTEND_IMAGE_REF:-}
BACKEND_IMAGE_REF=${BACKEND_IMAGE_REF:-}
DEMO_PUBLIC_HOST=${DEMO_PUBLIC_HOST:-}
DRY_RUN=${DRY_RUN:-false}

for binary in oc helm python3 "$ANSIBLE_PYTHON"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
[[ -d "$HELM_CHART_DIR" ]] || { echo "Missing Helm chart: $HELM_CHART_DIR" >&2; exit 1; }
export KUBECONFIG

if [[ -z "$DEMO_PUBLIC_HOST" ]]; then
  read -r CLUSTER_NAME BASE_DOMAIN < <(
    "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
print(cfg['okd_cluster_name'], cfg['okd_base_domain'])
PY
  )
  DEMO_PUBLIC_HOST="demo.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
fi

if [[ -z "$FRONTEND_IMAGE_REF" ]]; then
  FRONTEND_IMAGE_REF=$(oc get deployment demo-frontend -n "$DEMO_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
fi
if [[ -z "$BACKEND_IMAGE_REF" ]]; then
  BACKEND_IMAGE_REF=$(oc get deployment demo-backend -n "$DEMO_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
fi
[[ -n "$FRONTEND_IMAGE_REF" ]] || { echo "Unable to resolve FRONTEND_IMAGE_REF from env or existing demo-frontend Deployment." >&2; exit 1; }
[[ -n "$BACKEND_IMAGE_REF" ]] || { echo "Unable to resolve BACKEND_IMAGE_REF from env or existing demo-backend Deployment." >&2; exit 1; }

printf '%s\n' '============================================================'
printf '%s\n' ' demo-3tier Helm migration / first install'
printf '%s\n' '============================================================'
printf '  %-24s %s\n' 'Namespace' "$DEMO_NAMESPACE"
printf '  %-24s %s\n' 'Release' "$HELM_RELEASE"
printf '  %-24s %s\n' 'Chart' "$HELM_CHART_DIR"
printf '  %-24s %s\n' 'Frontend image' "$FRONTEND_IMAGE_REF"
printf '  %-24s %s\n' 'Backend image' "$BACKEND_IMAGE_REF"
printf '  %-24s %s\n' 'Route host' "$DEMO_PUBLIC_HOST"

oc get namespace "$DEMO_NAMESPACE" >/dev/null
oc get secret demo-postgres-credentials -n "$DEMO_NAMESPACE" >/dev/null
oc apply -f "$ROOT_DIR/applications/demo-3tier/openshift/imagestreams.yaml" >/dev/null

helm lint "$HELM_CHART_DIR" \
  --set-string frontend.image.ref="$FRONTEND_IMAGE_REF" \
  --set-string backend.image.ref="$BACKEND_IMAGE_REF" \
  --set-string route.host="$DEMO_PUBLIC_HOST"

if [[ "$DRY_RUN" == "true" ]]; then
  helm template "$HELM_RELEASE" "$HELM_CHART_DIR" \
    --namespace "$DEMO_NAMESPACE" \
    --set-string frontend.image.ref="$FRONTEND_IMAGE_REF" \
    --set-string backend.image.ref="$BACKEND_IMAGE_REF" \
    --set-string route.host="$DEMO_PUBLIC_HOST"
  exit 0
fi

wait_for_quota_status() {
  local quota_name="demo-3tier-quota"
  local attempt hard_configmaps used_configmaps hard_services used_services

  for attempt in $(seq 1 60); do
    hard_configmaps=$(oc get resourcequota "$quota_name" -n "$DEMO_NAMESPACE" -o jsonpath='{.status.hard.configmaps}' 2>/dev/null || true)
    used_configmaps=$(oc get resourcequota "$quota_name" -n "$DEMO_NAMESPACE" -o jsonpath='{.status.used.configmaps}' 2>/dev/null || true)
    hard_services=$(oc get resourcequota "$quota_name" -n "$DEMO_NAMESPACE" -o jsonpath='{.status.hard.services}' 2>/dev/null || true)
    used_services=$(oc get resourcequota "$quota_name" -n "$DEMO_NAMESPACE" -o jsonpath='{.status.used.services}' 2>/dev/null || true)

    if [[ -n "$hard_configmaps" && -n "$used_configmaps" && -n "$hard_services" && -n "$used_services" ]]; then
      printf 'ResourceQuota %s status is ready.\n' "$quota_name"
      return 0
    fi

    printf 'Waiting for ResourceQuota %s status to be calculated (%s/60)...\n' "$quota_name" "$attempt"
    sleep 2
  done

  oc describe resourcequota "$quota_name" -n "$DEMO_NAMESPACE" || true
  printf 'ResourceQuota %s status was not calculated in time.\n' "$quota_name" >&2
  return 1
}

apply_namespace_policies() {
  printf '\nPre-applying ResourceQuota/LimitRange before app objects.\n'
  helm template "$HELM_RELEASE" "$HELM_CHART_DIR" \
    --namespace "$DEMO_NAMESPACE" \
    --show-only templates/resourcequota.yaml \
    --show-only templates/limitrange.yaml \
    --set-string frontend.image.ref="$FRONTEND_IMAGE_REF" \
    --set-string backend.image.ref="$BACKEND_IMAGE_REF" \
    --set-string route.host="$DEMO_PUBLIC_HOST" | \
    oc apply -n "$DEMO_NAMESPACE" -f -

  wait_for_quota_status
}

if ! helm status "$HELM_RELEASE" -n "$DEMO_NAMESPACE" >/dev/null 2>&1; then
  printf '\nFirst Helm release not found. Cleaning legacy oc-apply runtime resources.\n'
  printf 'Keeping generated PostgreSQL Secret, ImageStreams and existing PostgreSQL PVC.\n'
  oc delete deployment demo-frontend demo-backend -n "$DEMO_NAMESPACE" --ignore-not-found --wait=true
  oc delete statefulset demo-postgres -n "$DEMO_NAMESPACE" --ignore-not-found --wait=true
  oc delete pod -l app=demo-postgres -n "$DEMO_NAMESPACE" --ignore-not-found --wait=true --timeout=5m
  oc delete service demo-frontend demo-backend demo-postgres -n "$DEMO_NAMESPACE" --ignore-not-found
  oc delete configmap demo-backend-config -n "$DEMO_NAMESPACE" --ignore-not-found
  oc delete route demo-3tier -n "$DEMO_NAMESPACE" --ignore-not-found
fi

apply_namespace_policies

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART_DIR" \
  --namespace "$DEMO_NAMESPACE" \
  --wait \
  --atomic \
  --timeout 10m \
  --history-max 10 \
  --set-string frontend.image.ref="$FRONTEND_IMAGE_REF" \
  --set-string backend.image.ref="$BACKEND_IMAGE_REF" \
  --set-string route.host="$DEMO_PUBLIC_HOST"

printf '\nHelm release and namespace policies:\n'
helm status "$HELM_RELEASE" -n "$DEMO_NAMESPACE"
oc get resourcequota demo-3tier-quota -n "$DEMO_NAMESPACE"
oc describe resourcequota demo-3tier-quota -n "$DEMO_NAMESPACE"
oc get limitrange demo-3tier-defaults -n "$DEMO_NAMESPACE"
oc describe limitrange demo-3tier-defaults -n "$DEMO_NAMESPACE"

"$ROOT_DIR/scripts/test-demo-3tier.sh"
