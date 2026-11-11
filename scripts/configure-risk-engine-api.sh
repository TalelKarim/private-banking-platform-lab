#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
KUBECONFIG=${KUBECONFIG:-$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig}
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
INVENTORY="$ANSIBLE_DIR/inventories/workloads/hosts.yml"
JENKINS_CONTROLLER_FLOATING_IP=${1:-${JENKINS_FLOATING_IP:-}}
JENKINS_CONTROLLER_SERVER_NAME=${JENKINS_CONTROLLER_SERVER_NAME:-jenkins-controller}
RISK_REPOSITORY_URL=${RISK_REPOSITORY_URL:-https://github.com/TalelKarim/private-banking-platform-lab.git}
RISK_NAMESPACE=${RISK_NAMESPACE:-banking}

for binary in oc helm "$ANSIBLE_PYTHON" "$ANSIBLE_PLAYBOOK"; do
  if [[ "$binary" == */* ]]; then
    [[ -x "$binary" ]] || { echo "Missing executable: $binary" >&2; exit 1; }
  else
    command -v "$binary" >/dev/null 2>&1 || { echo "Missing command: $binary" >&2; exit 1; }
  fi
done

[[ -r "$KUBECONFIG" ]] || { echo "Missing OKD kubeconfig: $KUBECONFIG" >&2; exit 1; }
export KUBECONFIG

read -r CLUSTER_NAME BASE_DOMAIN < <(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
print(cfg['okd_cluster_name'], cfg['okd_base_domain'])
PY
)

RISK_PUBLIC_HOST="risk.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

if [[ -z "$JENKINS_CONTROLLER_FLOATING_IP" ]]; then
  JENKINS_CONTROLLER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' risk-engine-api OpenShift/Jenkins configuration'
printf '%s\n' '============================================================'

printf '[1/4] Validating namespace, Jenkins RBAC and portfolio-java dependency...\n'
oc get namespace "$RISK_NAMESPACE" >/dev/null
oc get serviceaccount jenkins -n cicd >/dev/null
oc get service portfolio-java -n "$RISK_NAMESPACE" >/dev/null
for binding in jenkins-deployer jenkins-image-builder private-banking-image-pullers; do
  oc get rolebinding "$binding" -n "$RISK_NAMESPACE" >/dev/null
done
JENKINS_IDENTITY='system:serviceaccount:cicd:jenkins'
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create deployments -n "$RISK_NAMESPACE")" == "yes" ]]
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create routes.route.openshift.io/custom-host -n "$RISK_NAMESPACE")" == "yes" ]]
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create imagestreams.image.openshift.io -n "$RISK_NAMESPACE")" == "yes" ]]
[[ -n "$REGISTRY_HOST" ]] || { echo "OpenShift registry Route is missing." >&2; exit 1; }

printf '[2/4] Registering/reconciling managed Jenkins deployment job...\n'
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
(
  cd "$ANSIBLE_DIR"
  "$ANSIBLE_PLAYBOOK" \
    -i "$INVENTORY" \
    playbooks/configure-risk-engine-jenkins.yml \
    -e "jenkins_controller_ansible_host=$JENKINS_CONTROLLER_FLOATING_IP" \
    -e "jenkins_risk_registry_host=$REGISTRY_HOST" \
    -e "jenkins_risk_public_host=$RISK_PUBLIC_HOST" \
    -e "jenkins_risk_repository_url=$RISK_REPOSITORY_URL"
)

printf '[3/4] Linting Helm chart and validating service-discovery contract...\n'
helm lint "$ROOT_DIR/applications/risk-engine-api/helm/risk-engine-api" \
  --set-string image.ref='registry.local/banking/risk-engine-api@sha256:demo' \
  --set-string route.host="$RISK_PUBLIC_HOST" >/dev/null

RENDERED=$(helm template risk-engine-api "$ROOT_DIR/applications/risk-engine-api/helm/risk-engine-api" \
  --namespace "$RISK_NAMESPACE" \
  --set-string image.ref='registry.local/banking/risk-engine-api@sha256:demo' \
  --set-string route.host="$RISK_PUBLIC_HOST")
printf '%s' "$RENDERED" | grep -q 'PortfolioApi__BaseUrl: "http://portfolio-java:8080/"'
printf '    Internal dependency : http://portfolio-java:8080/\n'
printf '    DNS model           : risk pod -> Service portfolio-java -> Java pods\n'

printf '[4/4] Configuration summary...\n'
printf '  %-28s %s\n' 'Jenkins job' 'risk-engine-api-deploy'
printf '  %-28s %s\n' 'Namespace' "$RISK_NAMESPACE"
printf '  %-28s %s\n' 'Helm release' 'risk-engine-api'
printf '  %-28s %s\n' 'Java dependency' 'http://portfolio-java:8080/'
printf '  %-28s %s\n' 'Public URL' "https://$RISK_PUBLIC_HOST"
