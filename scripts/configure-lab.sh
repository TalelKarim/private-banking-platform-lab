#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JENKINS_CONTROLLER_SERVER_NAME=${JENKINS_CONTROLLER_SERVER_NAME:-jenkins-controller}
JENKINS_WORKER_SERVER_NAME=${JENKINS_WORKER_SERVER_NAME:-jenkins-agent-01}
POSTGRESQL_SERVER_NAME=${POSTGRESQL_SERVER_NAME:-postgresql}
OKD_LB_SERVER_NAME=${OKD_LB_SERVER_NAME:-okd-lb}
JENKINS_FLOATING_IP=${JENKINS_FLOATING_IP:-}
JENKINS_WORKER_FLOATING_IP=${JENKINS_WORKER_FLOATING_IP:-}
POSTGRESQL_FLOATING_IP=${POSTGRESQL_FLOATING_IP:-}
OKD_LB_FLOATING_IP=${OKD_LB_FLOATING_IP:-}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}

read -r LAB_BASE_DOMAIN OKD_CLUSTER_NAME < <(
  "$ANSIBLE_PYTHON" - "$ROOT_DIR/platform/openshift/cluster-config.yml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as handle:
    cfg = yaml.safe_load(handle)
print(cfg['okd_base_domain'], cfg['okd_cluster_name'])
PY
)

printf '%s\n' '============================================================'
printf '%s\n' ' Private Banking Platform Lab - Configuration convergence'
printf '%s\n' '============================================================'

# A Spot stop/start of the nested EC2 compute host leaves Nova guests SHUTOFF by
# default. Recover the known lab guests first; the Ansible runtime convergence
# later also installs the persistent Nova auto-resume setting for future boots.
printf '[1/24] Recovering known OpenStack guests after any lab-host reboot/Spot stop...\n'
"$ROOT_DIR/scripts/recover-openstack-guests.sh"

if [[ -z "$JENKINS_FLOATING_IP" ]]; then
  printf '[2/24] Discovering Jenkins controller floating IP from OpenStack...\n'
  JENKINS_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
  printf '      Jenkins controller floating IP: %s\n' "$JENKINS_FLOATING_IP"
else
  printf '[2/24] Using Jenkins controller floating IP override: %s\n' "$JENKINS_FLOATING_IP"
fi

if [[ -z "$JENKINS_WORKER_FLOATING_IP" ]]; then
  printf '[3/24] Discovering Jenkins worker floating IP from OpenStack...\n'
  JENKINS_WORKER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_WORKER_SERVER_NAME"
  )
  printf '      Jenkins worker floating IP: %s\n' "$JENKINS_WORKER_FLOATING_IP"
else
  printf '[3/24] Using Jenkins worker floating IP override: %s\n' "$JENKINS_WORKER_FLOATING_IP"
fi

if [[ -z "$POSTGRESQL_FLOATING_IP" ]]; then
  printf '[4/24] Discovering PostgreSQL floating IP from OpenStack...\n'
  POSTGRESQL_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$POSTGRESQL_SERVER_NAME"
  )
  printf '      PostgreSQL floating IP: %s\n' "$POSTGRESQL_FLOATING_IP"
else
  printf '[4/24] Using PostgreSQL floating IP override: %s\n' "$POSTGRESQL_FLOATING_IP"
fi

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  printf '[5/24] Discovering okd-lb floating IP from OpenStack...\n'
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
  printf '      okd-lb floating IP: %s\n' "$OKD_LB_FLOATING_IP"
else
  printf '[5/24] Using okd-lb floating IP override: %s\n' "$OKD_LB_FLOATING_IP"
fi

printf '[6/24] Converging OpenStack quotas, routed management forwarding and Nova guest recovery...\n'
"$ROOT_DIR/scripts/configure-openstack-runtime.sh"

wait_for_ssh() {
  local label=$1
  local host=$2
  local attempts=${SSH_READY_ATTEMPTS:-60}
  local interval=${SSH_READY_INTERVAL_SECONDS:-3}

  for attempt in $(seq 1 "$attempts"); do
    if timeout 2 bash -c "</dev/tcp/$host/22" 2>/dev/null; then
      printf '      %-22s SSH READY (%s:22)\n' "$label" "$host"
      return 0
    fi
    sleep "$interval"
  done

  echo "$label did not expose SSH on $host:22 after Nova reported ACTIVE." >&2
  return 1
}

printf '      Waiting for recovered workload operating systems to expose SSH...\n'
wait_for_ssh 'Jenkins controller' "$JENKINS_FLOATING_IP"
wait_for_ssh 'Jenkins worker' "$JENKINS_WORKER_FLOATING_IP"
wait_for_ssh 'PostgreSQL' "$POSTGRESQL_FLOATING_IP"
wait_for_ssh 'okd-lb' "$OKD_LB_FLOATING_IP"

printf '[7/24] Converging Jenkins controller with Ansible...\n'
"$ROOT_DIR/scripts/configure-jenkins.sh" "$JENKINS_FLOATING_IP"

printf '[8/24] Converging Jenkins worker and Remoting channel with Ansible...\n'
"$ROOT_DIR/scripts/configure-jenkins-worker.sh" \
  "$JENKINS_FLOATING_IP" \
  "$JENKINS_WORKER_FLOATING_IP"

printf '[9/24] Converging PostgreSQL and its Cinder-backed data layer with Ansible...\n'
"$ROOT_DIR/scripts/configure-postgresql.sh" "$POSTGRESQL_FLOATING_IP"

printf '[10/24] Converging edge gateway with Ansible...\n'
"$ROOT_DIR/scripts/configure-edge-gateway.sh" "$JENKINS_FLOATING_IP" "$OKD_LB_FLOATING_IP"

printf '[11/24] Converging OKD DNS/load-balancer foundation with Ansible...\n'
"$ROOT_DIR/scripts/configure-okd-lb.sh" "$OKD_LB_FLOATING_IP"

printf '[12/24] Configuring ops-runner OKD API resolution and SSH jump aliases...\n'
"$ROOT_DIR/scripts/configure-okd-client-access.sh" "$OKD_LB_FLOATING_IP"

printf '[13/24] Preparing pinned OKD installer tooling, Helm and matching SCOS Glance image...\n'
"$ROOT_DIR/scripts/prepare-okd-installation-prereqs.sh"

printf '[14/24] Generating and publishing fresh OKD installation assets...\n'
"$ROOT_DIR/scripts/prepare-okd-install-assets.sh" "$OKD_LB_FLOATING_IP"

printf '[15/24] Creating/converging OKD bootstrap + compact control-plane VMs...\n'
"$ROOT_DIR/scripts/okd-nodes.sh" apply

printf '[16/24] Completing OKD installation and retiring bootstrap...\n'
"$ROOT_DIR/scripts/complete-okd-installation.sh" "$OKD_LB_FLOATING_IP"

printf '[17/24] Installing/converging OpenStack Cinder CSI + default StorageClass...\n'
"$ROOT_DIR/scripts/configure-openshift-storage.sh"

printf '[18/24] Configuring the integrated OpenShift registry on persistent Cinder storage...\n'
"$ROOT_DIR/scripts/configure-openshift-registry.sh"

printf '[19/24] Converging the private Jenkins <-> OpenShift API/registry bridge and RBAC...\n'
"$ROOT_DIR/scripts/configure-openshift-cicd.sh" \
  "$JENKINS_FLOATING_IP" \
  "$JENKINS_WORKER_FLOATING_IP"

printf '[20/24] Running Jenkins build -> OpenShift registry push -> deployment smoke test...\n'
"$ROOT_DIR/scripts/test-openshift-cicd.sh" "$JENKINS_FLOATING_IP"

printf '[21/24] Validating the reusable OpenShift storage/registry/CI-CD foundation...\n'
export KUBECONFIG="$ROOT_DIR/.runtime/openshift/install/auth/kubeconfig"
oc get nodes
oc get csidriver cinder.csi.openstack.org
oc get storageclass
oc get pvc image-registry-storage -n openshift-image-registry
oc get clusteroperator image-registry
oc get serviceaccount jenkins -n cicd
oc get rolebinding jenkins-deployer jenkins-image-builder private-banking-image-pullers -n demo
oc rollout status deployment/phase2-smoke -n demo --timeout=2m

printf '[22/24] Configuring the demo-3tier runtime Secret and managed Jenkins deployment job...\n'
"$ROOT_DIR/scripts/configure-demo-3tier.sh" "$JENKINS_FLOATING_IP"

printf '[23/24] Building and deploying demo-3tier through Jenkins...\n'
"$ROOT_DIR/scripts/deploy-demo-3tier.sh" "$JENKINS_FLOATING_IP"

printf '[24/24] Final demo-3tier Route/application/persistence validation...\n'
"$ROOT_DIR/scripts/test-demo-3tier.sh"

printf '\n%s\n' '------------------------------------------------------------'
printf '%-28s %s\n' 'Jenkins controller' 'READY'
printf '%-28s %s\n' 'Jenkins worker' 'ONLINE'
printf '%-28s %s\n' 'PostgreSQL' 'READY'
printf '%-28s %s\n' 'Edge gateway' 'READY'
printf '%-28s %s\n' 'OKD DNS / LB' 'READY'
printf '%-28s %s\n' 'OKD install prereqs' 'READY'
printf '%-28s %s\n' 'OKD install assets' 'READY'
printf '%-28s %s\n' 'OKD cluster' 'INSTALLED'
printf '%-28s %s\n' 'OKD bootstrap' 'RETIRED'
printf '%-28s %s\n' 'Cinder CSI' 'READY'
printf '%-28s %s\n' 'StorageClass' 'cinder-standard (default)'
printf '%-28s %s\n' 'Image registry storage' 'PERSISTENT / CINDER'
printf '%-28s %s\n' 'Registry Jenkins Route' 'PRIVATE / PUBLIC EDGE BLOCKED'
printf '%-28s %s\n' 'Jenkins OpenShift RBAC' 'READY (cicd:jenkins -> demo)'
printf '%-28s %s\n' 'Jenkins registry smoke' 'SUCCESS'
printf '%-28s %s\n' 'demo-3tier Jenkins deploy' 'SUCCESS'
printf '%-28s %s\n' 'demo-3tier PostgreSQL' 'STATEFUL / CINDER'
printf '%-28s %s\n' 'demo-3tier public URL' "https://demo.apps.$OKD_CLUSTER_NAME.$LAB_BASE_DOMAIN"
printf '%-28s %s\n' 'Controller FIP' "$JENKINS_FLOATING_IP"
printf '%-28s %s\n' 'Worker FIP' "$JENKINS_WORKER_FLOATING_IP"
printf '%-28s %s\n' 'PostgreSQL FIP' "$POSTGRESQL_FLOATING_IP"
printf '%-28s %s\n' 'okd-lb FIP' "$OKD_LB_FLOATING_IP"
printf '%-28s %s\n' 'Jenkins URL' "https://jenkins.$LAB_BASE_DOMAIN"
printf '%-28s %s\n' 'Horizon URL' "https://cloud.$LAB_BASE_DOMAIN"
printf '%-28s %s\n' 'OpenShift Console' "https://console-openshift-console.apps.$OKD_CLUSTER_NAME.$LAB_BASE_DOMAIN"
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'LAB CONFIGURATION READY'
