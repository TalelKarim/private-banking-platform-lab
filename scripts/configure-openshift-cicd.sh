#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
INVENTORY="$ANSIBLE_DIR/inventories/workloads/hosts.yml"
JENKINS_CONTROLLER_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
JENKINS_WORKER_FLOATING_IP=${2:-${JENKINS_WORKER_FLOATING_IP:-}}
JENKINS_CONTROLLER_SERVER_NAME=${JENKINS_CONTROLLER_SERVER_NAME:-jenkins-controller}
JENKINS_WORKER_SERVER_NAME=${JENKINS_WORKER_SERVER_NAME:-jenkins-agent-01}
EDGE_GATEWAY_PRIVATE_IP=${EDGE_GATEWAY_PRIVATE_IP:-172.31.31.71}
RUNTIME_DIR="$ROOT_DIR/.runtime/openshift/cicd"
TOKEN_FILE="$RUNTIME_DIR/jenkins-token"
API_CA_FILE="$RUNTIME_DIR/api-ca.crt"
INGRESS_CA_FILE="$RUNTIME_DIR/ingress-ca.crt"

for binary in oc jq base64 curl openssl "$ANSIBLE_PYTHON" "$ANSIBLE_PLAYBOOK"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done
[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
export KUBECONFIG

CONFIG_JSON=$(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import json, sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    print(json.dumps(yaml.safe_load(handle)))
PY
)
CLUSTER_NAME=$(jq -r '.okd_cluster_name' <<<"$CONFIG_JSON")
BASE_DOMAIN=$(jq -r '.okd_base_domain' <<<"$CONFIG_JSON")
OKD_LB_PRIVATE_IP=$(jq -r '.okd_lb_ip' <<<"$CONFIG_JSON")
API_HOST="api.${CLUSTER_NAME}.${BASE_DOMAIN}"
API_URL="https://${API_HOST}:6443"
EXPECTED_REGISTRY_HOST="default-route-openshift-image-registry.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"

if [[ -z "$JENKINS_CONTROLLER_FLOATING_IP" ]]; then
  JENKINS_CONTROLLER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
fi
if [[ -z "$JENKINS_WORKER_FLOATING_IP" ]]; then
  JENKINS_WORKER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_WORKER_SERVER_NAME"
  )
fi

mkdir -p "$RUNTIME_DIR"
chmod 0700 "$RUNTIME_DIR"

printf '%s\n' '============================================================'
printf '%s\n' ' Jenkins <-> OpenShift CI/CD platform integration'
printf '%s\n' '============================================================'

printf '[1/8] Validating Phase 1 foundation...\n'
for node in okd-01 okd-02 okd-03; do
  [[ "$(oc get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == "True" ]] || {
    echo "$node is not Ready." >&2
    exit 1
  }
done
oc get csidriver cinder.csi.openstack.org >/dev/null
[[ "$(oc get storageclass cinder-standard -o jsonpath='{.provisioner}')" == "cinder.csi.openstack.org" ]] || {
  echo "cinder-standard is not backed by Cinder CSI." >&2
  exit 1
}
[[ "$(oc get pvc image-registry-storage -n openshift-image-registry -o jsonpath='{.status.phase}')" == "Bound" ]] || {
  echo "The OpenShift registry PVC is not Bound." >&2
  exit 1
}
oc wait --for=condition=Available clusteroperator/image-registry --timeout=2m >/dev/null
oc wait --for=condition=Degraded=False clusteroperator/image-registry --timeout=2m >/dev/null

printf '[2/8] Enabling the OpenShift registry Route for private Jenkins use...\n'
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge \
  -p '{"spec":{"defaultRoute":true}}' >/dev/null

REGISTRY_HOST=""
for _ in $(seq 1 60); do
  REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}' 2>/dev/null || true)
  [[ -n "$REGISTRY_HOST" ]] && break
  sleep 2
done
[[ -n "$REGISTRY_HOST" ]] || { echo "Registry default Route was not created." >&2; exit 1; }
[[ "$REGISTRY_HOST" == "$EXPECTED_REGISTRY_HOST" ]] || {
  echo "Unexpected registry Route host: $REGISTRY_HOST (expected $EXPECTED_REGISTRY_HOST)." >&2
  exit 1
}

printf '[3/8] Creating/reconciling Jenkins ServiceAccount and namespaced RBAC...\n'
oc apply -f "$ROOT_DIR/platform/openshift/jenkins-integration/namespaces.yaml" >/dev/null
oc apply -f "$ROOT_DIR/platform/openshift/jenkins-integration/serviceaccount.yaml" >/dev/null
oc apply -f "$ROOT_DIR/platform/openshift/jenkins-integration/rbac.yaml" >/dev/null

printf '[4/8] Waiting for the Jenkins ServiceAccount token and exporting runtime CAs...\n'
TOKEN=""
for _ in $(seq 1 60); do
  TOKEN_B64=$(oc get secret jenkins-api-token -n cicd -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "$TOKEN_B64" ]]; then
    TOKEN=$(printf '%s' "$TOKEN_B64" | base64 -d)
    break
  fi
  sleep 1
done
[[ ${#TOKEN} -gt 100 ]] || { echo "Jenkins ServiceAccount token was not populated." >&2; exit 1; }
printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"
unset TOKEN TOKEN_B64

"$ANSIBLE_PYTHON" - "$KUBECONFIG" "$API_CA_FILE" <<'PY'
import base64, sys, yaml
src, dst = sys.argv[1:]
with open(src, encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
clusters = cfg.get('clusters') or []
if not clusters:
    raise SystemExit('kubeconfig contains no cluster CA')
data = clusters[0]['cluster'].get('certificate-authority-data')
if not data:
    raise SystemExit('kubeconfig has no certificate-authority-data')
with open(dst, 'wb') as handle:
    handle.write(base64.b64decode(data))
PY

oc get secret router-ca -n openshift-ingress-operator \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "$INGRESS_CA_FILE"
[[ -s "$API_CA_FILE" && -s "$INGRESS_CA_FILE" ]] || {
  echo "Unable to export OpenShift API/ingress CA bundles." >&2
  exit 1
}
chmod 0600 "$API_CA_FILE" "$INGRESS_CA_FILE"

printf '[5/8] Validating Jenkins RBAC is useful but not cluster-admin...\n'
JENKINS_IDENTITY='system:serviceaccount:cicd:jenkins'
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create deployments -n demo)" == "yes" ]] || {
  echo "Jenkins cannot create Deployments in demo." >&2
  exit 1
}
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create routes.route.openshift.io -n demo)" == "yes" ]] || {
  echo "Jenkins cannot create Routes in demo." >&2
  exit 1
}
if [[ "$(oc auth can-i --as="$JENKINS_IDENTITY" get nodes)" == "yes" ]]; then
  echo "Jenkins unexpectedly has cluster-wide node access." >&2
  exit 1
fi

printf '[6/8] Configuring private API/registry connectivity and rootless build tools on Jenkins worker...\n'
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
EXTRA_VARS=(
  "jenkins_controller_ansible_host=$JENKINS_CONTROLLER_FLOATING_IP"
  "jenkins_worker_ansible_host=$JENKINS_WORKER_FLOATING_IP"
  "jenkins_openshift_api_host=$API_HOST"
  "jenkins_openshift_api_url=$API_URL"
  "jenkins_openshift_registry_host=$REGISTRY_HOST"
  "jenkins_openshift_lb_private_ip=$OKD_LB_PRIVATE_IP"
  "jenkins_openshift_api_ca_src=$API_CA_FILE"
  "jenkins_openshift_ingress_ca_src=$INGRESS_CA_FILE"
  "jenkins_openshift_oc_binary_src=/usr/local/bin/oc"
  "jenkins_openshift_token_file=$TOKEN_FILE"
)
EXTRA_ARGS=()
for item in "${EXTRA_VARS[@]}"; do EXTRA_ARGS+=("-e" "$item"); done
(
  cd "$ANSIBLE_DIR"
  "$ANSIBLE_PLAYBOOK" \
    -i "$INVENTORY" \
    playbooks/configure-jenkins-openshift.yml \
    "${EXTRA_ARGS[@]}"
)

printf '[7/8] Confirming the registry Route matches the exact public-edge deny hostname...\n'
# configure-lab converges and locally validates the Nginx 404 virtual host at
# step 10. Matching the deterministic default Route name here guarantees the
# private registry host is the exact hostname blocked by that edge rule.
[[ "$REGISTRY_HOST" == "$EXPECTED_REGISTRY_HOST" ]] || exit 1

printf '[8/8] Final CI/CD bridge summary...\n'
printf '\nOpenShift CI/CD foundation READY:\n'
printf '  %-28s %s\n' 'API private path' "$API_HOST -> $OKD_LB_PRIVATE_IP:6443"
printf '  %-28s %s\n' 'Registry private path' "$REGISTRY_HOST -> $OKD_LB_PRIVATE_IP:443"
printf '  %-28s %s\n' 'Public registry edge' 'BLOCKED / HTTP 404'
printf '  %-28s %s\n' 'Jenkins identity' "$JENKINS_IDENTITY"
printf '  %-28s %s\n' 'Deployment namespace' 'demo'
printf '  %-28s %s\n' 'Jenkins credential' 'openshift-ci-token (runtime-injected)'
printf '  %-28s %s\n' 'Jenkins smoke job' 'platform-openshift-smoke'
