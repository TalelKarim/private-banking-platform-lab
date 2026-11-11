#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
OKD_LB_SERVER_NAME=${OKD_LB_SERVER_NAME:-okd-lb}
OKD_LB_FLOATING_IP=${OKD_LB_FLOATING_IP:-}
INGRESS_CA="$ROOT_DIR/.runtime/openshift/cicd/ingress-ca.crt"
NAMESPACE=${RISK_NAMESPACE:-banking}

for binary in oc helm curl python3 "$ANSIBLE_PYTHON"; do
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

RISK_HOST="risk.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' risk-engine-api OpenShift validation'
printf '%s\n' '============================================================'

printf '[1/5] Waiting for ASP.NET Core deployment readiness...\n'
oc rollout status deployment/risk-engine-api -n "$NAMESPACE" --timeout=5m

printf '[2/5] Validating Helm, Route, ConfigMap and immutable image...\n'
helm status risk-engine-api -n "$NAMESPACE" >/dev/null
oc get service portfolio-java -n "$NAMESPACE" >/dev/null
[[ "$(oc get route risk-engine-api -n "$NAMESPACE" -o jsonpath='{.spec.host}')" == "$RISK_HOST" ]] || {
  echo "Unexpected risk-engine-api Route hostname." >&2
  exit 1
}

IMAGE=$(oc get deployment risk-engine-api -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "$IMAGE" == *@sha256:* ]] || { echo "risk-engine-api is not pinned to an immutable digest: $IMAGE" >&2; exit 1; }

BASE_URL=$(oc get configmap risk-engine-api-config -n "$NAMESPACE" -o jsonpath='{.data.PortfolioApi__BaseUrl}')
[[ "$BASE_URL" == "http://portfolio-java:8080/" ]] || {
  echo "Unexpected PortfolioApi__BaseUrl: $BASE_URL" >&2
  exit 1
}

printf '[3/5] Exercising liveness and readiness through the OpenShift Route...\n'
LIVE=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${RISK_HOST}:443:${OKD_LB_FLOATING_IP}" \
  "https://${RISK_HOST}/health/live")
[[ "$LIVE" == "Healthy" ]]

READY=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${RISK_HOST}:443:${OKD_LB_FLOATING_IP}" \
  "https://${RISK_HOST}/health/ready")
[[ "$READY" == "Healthy" ]]
printf '    Liveness + readiness: OK\n'

printf '[4/5] Exercising Route -> .NET -> portfolio-java Service -> PostgreSQL VM...\n'
RESPONSE=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${RISK_HOST}:443:${OKD_LB_FLOATING_IP}" \
  -H 'Content-Type: application/json' \
  -d '{"portfolioId":1,"marketVolatility":0.35,"concentrationRatio":0.40,"leverageRatio":0.10}' \
  "https://${RISK_HOST}/risk/calculate")

printf '%s' "$RESPONSE" | python3 -c '
import json, sys
r = json.load(sys.stdin)
assert r["portfolioId"] == 1
assert float(r["score"]) == 31.5
assert r["level"] == "MEDIUM"
assert r["portfolioValue"] > 0
'
printf '    Risk calculation returned portfolio data and expected score: OK\n'

printf '[5/5] Final resource inventory...\n'
oc get deployment,service,route,configmap -n "$NAMESPACE" -l app.kubernetes.io/name=risk-engine-api
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=risk-engine-api -o wide
oc get imagestream risk-engine-api -n "$NAMESPACE"

printf '\nRISK-ENGINE-API END-TO-END VALIDATION: SUCCESS\n'
printf 'Public ingress URL: https://%s\n' "$RISK_HOST"
printf 'Internal dependency: risk-engine-api -> http://portfolio-java:8080 -> Java pods -> PostgreSQL 10.10.0.40:5432.\n'
