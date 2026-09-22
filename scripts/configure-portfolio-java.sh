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
PORTFOLIO_REPOSITORY_URL=${PORTFOLIO_REPOSITORY_URL:-https://github.com/TalelKarim/private-banking-platform-lab.git}
PORTFOLIO_NAMESPACE=${PORTFOLIO_NAMESPACE:-banking}
PORTFOLIO_DB_SECRET=${PORTFOLIO_DB_SECRET:-portfolio-java-db}
POSTGRESQL_PRIVATE_IP=${POSTGRESQL_PRIVATE_IP:-10.10.0.40}
POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE:-portfolio}
POSTGRESQL_SCHEMA=${POSTGRESQL_SCHEMA:-portfolio}
POSTGRESQL_APP_USER=${POSTGRESQL_APP_USER:-portfolio_app}
POSTGRESQL_PASSWORD_PARAMETER=${POSTGRESQL_PASSWORD_PARAMETER:-/private-banking-platform-lab/postgresql/portfolio-app-password}
AWS_REGION=${AWS_REGION:-eu-south-2}

for binary in oc helm jq aws "$ANSIBLE_PYTHON" "$ANSIBLE_PLAYBOOK"; do
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
PORTFOLIO_PUBLIC_HOST="portfolio.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
REGISTRY_HOST=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

if [[ -z "$JENKINS_CONTROLLER_FLOATING_IP" ]]; then
  JENKINS_CONTROLLER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
fi

printf '%s\n' '============================================================'
printf '%s\n' ' portfolio-java OpenShift/Jenkins configuration'
printf '%s\n' '============================================================'

printf '[1/5] Validating Jenkins/OpenShift RBAC in namespace %s...\n' "$PORTFOLIO_NAMESPACE"
oc get namespace "$PORTFOLIO_NAMESPACE" >/dev/null
oc get serviceaccount jenkins -n cicd >/dev/null
for binding in jenkins-deployer jenkins-image-builder private-banking-image-pullers; do
  oc get rolebinding "$binding" -n "$PORTFOLIO_NAMESPACE" >/dev/null
done
JENKINS_IDENTITY='system:serviceaccount:cicd:jenkins'
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create deployments -n "$PORTFOLIO_NAMESPACE")" == "yes" ]]
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create routes.route.openshift.io/custom-host -n "$PORTFOLIO_NAMESPACE")" == "yes" ]]
[[ "$(oc auth can-i --as="$JENKINS_IDENTITY" create imagestreams.image.openshift.io -n "$PORTFOLIO_NAMESPACE")" == "yes" ]]
[[ -n "$REGISTRY_HOST" ]] || { echo "OpenShift registry Route is missing." >&2; exit 1; }

printf '[2/5] Syncing PostgreSQL application credential from AWS SSM into OpenShift Secret...\n'
SECRET_DIR=$(mktemp -d /tmp/portfolio-java-secret.XXXXXX)
cleanup() { rm -rf "$SECRET_DIR"; }
trap cleanup EXIT
chmod 0700 "$SECRET_DIR"
printf '%s' "$POSTGRESQL_APP_USER" > "$SECRET_DIR/SPRING_DATASOURCE_USERNAME"
aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$POSTGRESQL_PASSWORD_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$SECRET_DIR/SPRING_DATASOURCE_PASSWORD"
chmod 0600 "$SECRET_DIR"/*
oc create secret generic "$PORTFOLIO_DB_SECRET" \
  -n "$PORTFOLIO_NAMESPACE" \
  --from-file=SPRING_DATASOURCE_USERNAME="$SECRET_DIR/SPRING_DATASOURCE_USERNAME" \
  --from-file=SPRING_DATASOURCE_PASSWORD="$SECRET_DIR/SPRING_DATASOURCE_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
oc label secret "$PORTFOLIO_DB_SECRET" -n "$PORTFOLIO_NAMESPACE" \
  app.kubernetes.io/part-of=private-banking-platform-lab \
  app.kubernetes.io/name=portfolio-java \
  private-banking-platform-lab/managed-by=platform \
  --overwrite >/dev/null
rm -rf "$SECRET_DIR"
trap - EXIT
printf '    Secret %s/%s synchronized without storing the password in Git.\n' "$PORTFOLIO_NAMESPACE" "$PORTFOLIO_DB_SECRET"

printf '[3/5] Registering/reconciling managed Jenkins deployment job...\n'
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
(
  cd "$ANSIBLE_DIR"
  "$ANSIBLE_PLAYBOOK" \
    -i "$INVENTORY" \
    playbooks/configure-portfolio-java-jenkins.yml \
    -e "jenkins_controller_ansible_host=$JENKINS_CONTROLLER_FLOATING_IP" \
    -e "jenkins_portfolio_registry_host=$REGISTRY_HOST" \
    -e "jenkins_portfolio_public_host=$PORTFOLIO_PUBLIC_HOST" \
    -e "jenkins_portfolio_repository_url=$PORTFOLIO_REPOSITORY_URL"
)

printf '[4/5] Linting Helm chart and validating DB network contract...\n'
DB_URL="jdbc:postgresql://${POSTGRESQL_PRIVATE_IP}:5432/${POSTGRESQL_DATABASE}?currentSchema=${POSTGRESQL_SCHEMA}"
helm lint "$ROOT_DIR/applications/portfolio-java/helm/portfolio-java" \
  --set-string image.ref='registry.local/banking/portfolio-java@sha256:demo' \
  --set-string route.host="$PORTFOLIO_PUBLIC_HOST" \
  --set-string config.datasourceUrl="$DB_URL" >/dev/null
# Network design contract: Neutron lab-router already has interfaces on both
# 10.10.0.0/24 and 10.20.0.0/24. Terraform permits PostgreSQL/5432 from the
# OpenShift machine CIDR; Ansible pg_hba.conf permits SCRAM from the same CIDR.
printf '    DB target          : %s:5432/%s schema=%s\n' "$POSTGRESQL_PRIVATE_IP" "$POSTGRESQL_DATABASE" "$POSTGRESQL_SCHEMA"
printf '    OpenShift clients  : 10.20.0.0/24 -> Neutron lab-router -> 10.10.0.40\n'
printf '    Auth               : SCRAM / user %s / password from SSM -> OpenShift Secret\n' "$POSTGRESQL_APP_USER"

printf '[5/5] Configuration summary...\n'
printf '  %-28s %s\n' 'Jenkins job' 'portfolio-java-deploy'
printf '  %-28s %s\n' 'Namespace' "$PORTFOLIO_NAMESPACE"
printf '  %-28s %s\n' 'Helm release' 'portfolio-java'
printf '  %-28s %s\n' 'Database Secret' "$PORTFOLIO_DB_SECRET"
printf '  %-28s %s\n' 'Database' "$POSTGRESQL_PRIVATE_IP:5432/$POSTGRESQL_DATABASE"
printf '  %-28s %s\n' 'Public URL' "https://$PORTFOLIO_PUBLIC_HOST"
