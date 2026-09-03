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
JENKINS_CONTROLLER_SERVER_NAME=${JENKINS_CONTROLLER_SERVER_NAME:-jenkins-controller}
DEMO_REPOSITORY_URL=${DEMO_REPOSITORY_URL:-https://github.com/TalelKarim/private-banking-platform-lab.git}
DEMO_NAMESPACE=${DEMO_NAMESPACE:-demo}
DEMO_DB_SECRET=${DEMO_DB_SECRET:-demo-postgres-credentials}

for binary in oc openssl jq "$ANSIBLE_PYTHON" "$ANSIBLE_PLAYBOOK"; do
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
DEMO_PUBLIC_HOST="demo.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

if [[ -z "$JENKINS_CONTROLLER_FLOATING_IP" ]]; then
  JENKINS_CONTROLLER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' demo-3tier application platform configuration'
printf '%s\n' '============================================================'

printf '[1/5] Validating the Phase 2 Jenkins/OpenShift foundation...\n'
oc get namespace "$DEMO_NAMESPACE" >/dev/null
oc get serviceaccount jenkins -n cicd >/dev/null
oc get rolebinding jenkins-deployer jenkins-image-builder private-banking-image-pullers -n "$DEMO_NAMESPACE" >/dev/null
[[ "$(oc auth can-i --as=system:serviceaccount:cicd:jenkins create statefulsets.apps -n "$DEMO_NAMESPACE")" == "yes" ]] || {
  echo "Jenkins cannot create StatefulSets in $DEMO_NAMESPACE." >&2
  exit 1
}
[[ "$(oc auth can-i --as=system:serviceaccount:cicd:jenkins create persistentvolumeclaims -n "$DEMO_NAMESPACE")" == "yes" ]] || {
  echo "Jenkins cannot create PVCs in $DEMO_NAMESPACE." >&2
  exit 1
}
[[ "$(oc auth can-i --as=system:serviceaccount:cicd:jenkins create routes.route.openshift.io/custom-host -n "$DEMO_NAMESPACE")" == "yes" ]] || {
  echo "Jenkins cannot create a Route with an explicit host in $DEMO_NAMESPACE." >&2
  exit 1
}
[[ -n "$REGISTRY_HOST" ]] || { echo "OpenShift registry Route is missing." >&2; exit 1; }

printf '[2/5] Ensuring runtime-only PostgreSQL application credentials...\n'
if oc get secret "$DEMO_DB_SECRET" -n "$DEMO_NAMESPACE" >/dev/null 2>&1; then
  for key in POSTGRESQL_USER POSTGRESQL_PASSWORD POSTGRESQL_DATABASE; do
    value=$(oc get secret "$DEMO_DB_SECRET" -n "$DEMO_NAMESPACE" -o "jsonpath={.data.${key}}")
    [[ -n "$value" ]] || { echo "$DEMO_DB_SECRET is missing key $key." >&2; exit 1; }
  done
  printf '    Reusing existing Secret %s/%s\n' "$DEMO_NAMESPACE" "$DEMO_DB_SECRET"
else
  DB_PASSWORD=$(openssl rand -hex 24)
  oc create secret generic "$DEMO_DB_SECRET" \
    -n "$DEMO_NAMESPACE" \
    --from-literal=POSTGRESQL_USER=demo_app \
    --from-literal=POSTGRESQL_PASSWORD="$DB_PASSWORD" \
    --from-literal=POSTGRESQL_DATABASE=demo_portfolio \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc label secret "$DEMO_DB_SECRET" -n "$DEMO_NAMESPACE" \
    app.kubernetes.io/part-of=demo-3tier \
    private-banking-platform-lab/managed-by=platform \
    --overwrite >/dev/null
  unset DB_PASSWORD
  printf '    Created generated Secret %s/%s (value never stored in Git)\n' "$DEMO_NAMESPACE" "$DEMO_DB_SECRET"
fi

printf '[3/5] Registering/reconciling managed Jenkins deployment job...\n'
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
(
  cd "$ANSIBLE_DIR"
  "$ANSIBLE_PLAYBOOK" \
    -i "$INVENTORY" \
    playbooks/configure-demo-3tier-jenkins.yml \
    -e "jenkins_controller_ansible_host=$JENKINS_CONTROLLER_FLOATING_IP" \
    -e "jenkins_demo_registry_host=$REGISTRY_HOST" \
    -e "jenkins_demo_public_host=$DEMO_PUBLIC_HOST" \
    -e "jenkins_demo_repository_url=$DEMO_REPOSITORY_URL"
)

printf '[4/5] Verifying application storage and public-ingress prerequisites...\n'
[[ "$(oc get storageclass cinder-standard -o jsonpath='{.provisioner}')" == "cinder.csi.openstack.org" ]] || {
  echo "cinder-standard is not backed by Cinder CSI." >&2
  exit 1
}
# The wildcard Route53/ALB/Nginx ingress was created before Phase 3. The app
# only needs a normal OpenShift Route under that existing wildcard hostname.
printf '    Persistent storage : cinder-standard\n'
printf '    Public Route host   : %s\n' "$DEMO_PUBLIC_HOST"

printf '[5/5] Final Phase 3 configuration summary...\n'
printf '\ndemo-3tier deployment foundation READY:\n'
printf '  %-28s %s\n' 'Jenkins job' 'demo-3tier-deploy'
printf '  %-28s %s\n' 'Jenkins identity' 'system:serviceaccount:cicd:jenkins'
printf '  %-28s %s\n' 'Application namespace' "$DEMO_NAMESPACE"
printf '  %-28s %s\n' 'Database Secret' "$DEMO_DB_SECRET (generated)"
printf '  %-28s %s\n' 'Database storage' 'StatefulSet -> PVC -> cinder-standard'
printf '  %-28s %s\n' 'Public application URL' "https://$DEMO_PUBLIC_HOST"
printf '  %-28s %s\n' 'Source repository' "$DEMO_REPOSITORY_URL"
