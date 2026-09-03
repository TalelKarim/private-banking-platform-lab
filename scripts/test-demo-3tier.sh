#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
OKD_LB_SERVER_NAME=${OKD_LB_SERVER_NAME:-okd-lb}
OKD_LB_FLOATING_IP=${OKD_LB_FLOATING_IP:-}
INGRESS_CA="$ROOT_DIR/.runtime/openshift/cicd/ingress-ca.crt"

for binary in oc curl python3 "$ANSIBLE_PYTHON"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
[[ -r "$INGRESS_CA" ]] || { echo "Missing OpenShift ingress CA: $INGRESS_CA" >&2; exit 1; }
export KUBECONFIG

read -r CLUSTER_NAME BASE_DOMAIN < <(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
print(cfg['okd_cluster_name'], cfg['okd_base_domain'])
PY
)
DEMO_HOST="demo.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' demo-3tier OpenShift validation'
printf '%s\n' '============================================================'

printf '[1/6] Waiting for application controllers...\n'
oc rollout status statefulset/demo-postgres -n demo --timeout=3m
oc rollout status deployment/demo-backend -n demo --timeout=3m
oc rollout status deployment/demo-frontend -n demo --timeout=3m

printf '[2/6] Validating Cinder-backed PostgreSQL persistence...\n'
PVC=postgres-data-demo-postgres-0
[[ "$(oc get pvc "$PVC" -n demo -o jsonpath='{.status.phase}')" == "Bound" ]] || {
  echo "$PVC is not Bound." >&2
  exit 1
}
PV=$(oc get pvc "$PVC" -n demo -o jsonpath='{.spec.volumeName}')
CINDER_VOLUME=$(oc get pv "$PV" -o jsonpath='{.spec.csi.volumeHandle}')
[[ -n "$CINDER_VOLUME" ]] || { echo "Unable to resolve the Cinder volume handle." >&2; exit 1; }
printf '    PVC            %s\n' "$PVC"
printf '    PV             %s\n' "$PV"
printf '    Cinder volume  %s\n' "$CINDER_VOLUME"

printf '[3/6] Validating Services, Route and immutable image references...\n'
for service in demo-postgres demo-backend demo-frontend; do oc get service "$service" -n demo >/dev/null; done
[[ "$(oc get route demo-3tier -n demo -o jsonpath='{.spec.host}')" == "$DEMO_HOST" ]] || {
  echo "Unexpected demo Route hostname." >&2
  exit 1
}
for deployment in demo-backend demo-frontend; do
  image=$(oc get deployment "$deployment" -n demo -o jsonpath='{.spec.template.spec.containers[0].image}')
  [[ "$image" == *@sha256:* ]] || { echo "$deployment is not pinned to an immutable digest: $image" >&2; exit 1; }
done

printf '[4/6] Exercising the complete in-cluster 3-tier request path...\n'
oc exec deployment/demo-backend -n demo -- \
  python -c 'import json,urllib.request; p=json.load(urllib.request.urlopen("http://demo-frontend/api/portfolio", timeout=10)); assert p["application"] == "private-banking-demo-3tier"; assert len(p["positions"]) >= 4; print(json.dumps(p, indent=2))'

printf '[5/6] Exercising the OpenShift Route directly through okd-lb with real ingress TLS...\n'
PAYLOAD=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${DEMO_HOST}:443:${OKD_LB_FLOATING_IP}" \
  "https://${DEMO_HOST}/api/portfolio")
printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["application"] == "private-banking-demo-3tier"; assert len(p["positions"]) >= 4'
printf '    Route TLS + frontend proxy + backend + PostgreSQL: OK\n'

printf '[6/6] Final resource inventory...\n'
oc get deployment,statefulset,service,route -n demo -l app.kubernetes.io/part-of=demo-3tier
oc get pods -n demo -l app.kubernetes.io/part-of=demo-3tier -o wide
oc get pvc -n demo -l app.kubernetes.io/part-of=demo-3tier
oc get imagestream demo-frontend demo-backend -n demo

printf '\nDEMO-3TIER END-TO-END VALIDATION: SUCCESS\n'
printf 'Public ingress URL: https://%s\n' "$DEMO_HOST"
printf 'Note: the AWS ALB is Internet-facing but intentionally restricted to the lab client CIDR/cloud-browser by Security Group.\n'
