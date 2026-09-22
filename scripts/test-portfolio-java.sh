#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
OKD_LB_SERVER_NAME=${OKD_LB_SERVER_NAME:-okd-lb}
OKD_LB_FLOATING_IP=${OKD_LB_FLOATING_IP:-}
INGRESS_CA="$ROOT_DIR/.runtime/openshift/cicd/ingress-ca.crt"
NAMESPACE=${PORTFOLIO_NAMESPACE:-banking}

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
PORTFOLIO_HOST="portfolio.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' portfolio-java OpenShift validation'
printf '%s\n' '============================================================'

printf '[1/4] Waiting for Spring Boot deployment readiness...\n'
oc rollout status deployment/portfolio-java -n "$NAMESPACE" --timeout=5m

printf '[2/4] Validating Helm, Route, Secret and immutable image...\n'
helm status portfolio-java -n "$NAMESPACE" >/dev/null
oc get secret portfolio-java-db -n "$NAMESPACE" >/dev/null
[[ "$(oc get route portfolio-java -n "$NAMESPACE" -o jsonpath='{.spec.host}')" == "$PORTFOLIO_HOST" ]] || {
  echo "Unexpected portfolio Route hostname." >&2
  exit 1
}
IMAGE=$(oc get deployment portfolio-java -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ "$IMAGE" == *@sha256:* ]] || { echo "portfolio-java is not pinned to an immutable digest: $IMAGE" >&2; exit 1; }

printf '[3/4] Exercising Route -> Spring Boot -> Hibernate/Flyway -> PostgreSQL VM...\n'
HEALTH=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${PORTFOLIO_HOST}:443:${OKD_LB_FLOATING_IP}" \
  "https://${PORTFOLIO_HOST}/actuator/health")
printf '%s' "$HEALTH" | python3 -c 'import json,sys; h=json.load(sys.stdin); assert h["status"] == "UP"'

PORTFOLIOS=$(curl --fail --silent --show-error \
  --cacert "$INGRESS_CA" \
  --resolve "${PORTFOLIO_HOST}:443:${OKD_LB_FLOATING_IP}" \
  "https://${PORTFOLIO_HOST}/portfolios")
printf '%s' "$PORTFOLIOS" | python3 -c 'import json,sys; p=json.load(sys.stdin); assert isinstance(p,list) and len(p) >= 3'
printf '    Health UP and portfolio rows returned from external PostgreSQL: OK\n'

printf '[4/4] Final resource inventory...\n'
oc get deployment,service,route,configmap -n "$NAMESPACE" -l app.kubernetes.io/name=portfolio-java
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=portfolio-java -o wide
oc get imagestream portfolio-java -n "$NAMESPACE"

printf '\nPORTFOLIO-JAVA END-TO-END VALIDATION: SUCCESS\n'
printf 'Public ingress URL: https://%s\n' "$PORTFOLIO_HOST"
printf 'DB path validated indirectly by readiness + GET: Pod -> node SNAT (10.20.0.0/24) -> Neutron lab-router -> PostgreSQL 10.10.0.40:5432.\n'
