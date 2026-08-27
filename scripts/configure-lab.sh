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

printf '%s\n' '============================================================'
printf '%s\n' ' Private Banking Platform Lab - Configuration convergence'
printf '%s\n' '============================================================'

if [[ -z "$JENKINS_FLOATING_IP" ]]; then
  printf '[1/12] Discovering Jenkins controller floating IP from OpenStack...\n'
  JENKINS_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_CONTROLLER_SERVER_NAME"
  )
  printf '      Jenkins controller floating IP: %s\n' "$JENKINS_FLOATING_IP"
else
  printf '[1/12] Using Jenkins controller floating IP override: %s\n' "$JENKINS_FLOATING_IP"
fi

if [[ -z "$JENKINS_WORKER_FLOATING_IP" ]]; then
  printf '[2/12] Discovering Jenkins worker floating IP from OpenStack...\n'
  JENKINS_WORKER_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_WORKER_SERVER_NAME"
  )
  printf '      Jenkins worker floating IP: %s\n' "$JENKINS_WORKER_FLOATING_IP"
else
  printf '[2/12] Using Jenkins worker floating IP override: %s\n' "$JENKINS_WORKER_FLOATING_IP"
fi

if [[ -z "$POSTGRESQL_FLOATING_IP" ]]; then
  printf '[3/12] Discovering PostgreSQL floating IP from OpenStack...\n'
  POSTGRESQL_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$POSTGRESQL_SERVER_NAME"
  )
  printf '      PostgreSQL floating IP: %s\n' "$POSTGRESQL_FLOATING_IP"
else
  printf '[3/12] Using PostgreSQL floating IP override: %s\n' "$POSTGRESQL_FLOATING_IP"
fi

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  printf '[4/12] Discovering okd-lb floating IP from OpenStack...\n'
  OKD_LB_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$OKD_LB_SERVER_NAME"
  )
  printf '      okd-lb floating IP: %s\n' "$OKD_LB_FLOATING_IP"
else
  printf '[4/12] Using okd-lb floating IP override: %s\n' "$OKD_LB_FLOATING_IP"
fi

printf '[5/12] Converging Jenkins controller with Ansible...\n'
"$ROOT_DIR/scripts/configure-jenkins.sh" "$JENKINS_FLOATING_IP"

printf '[6/12] Converging Jenkins worker and Remoting channel with Ansible...\n'
"$ROOT_DIR/scripts/configure-jenkins-worker.sh" \
  "$JENKINS_FLOATING_IP" \
  "$JENKINS_WORKER_FLOATING_IP"

printf '[7/12] Converging PostgreSQL and its Cinder-backed data layer with Ansible...\n'
"$ROOT_DIR/scripts/configure-postgresql.sh" "$POSTGRESQL_FLOATING_IP"

printf '[8/12] Converging edge gateway with Ansible...\n'
"$ROOT_DIR/scripts/configure-edge-gateway.sh" "$JENKINS_FLOATING_IP"

printf '[9/12] Converging OKD DNS/load-balancer foundation with Ansible...\n'
"$ROOT_DIR/scripts/configure-okd-lb.sh" "$OKD_LB_FLOATING_IP"

printf '[10/12] Preparing pinned OKD installer tooling and matching SCOS Glance image...\n'
"$ROOT_DIR/scripts/prepare-okd-installation-prereqs.sh"

printf '[11/12] Generating and publishing fresh OKD installation assets...\n'
"$ROOT_DIR/scripts/prepare-okd-install-assets.sh" "$OKD_LB_FLOATING_IP"

printf '[12/12] Creating OKD bootstrap + compact control-plane VMs...\n'
"$ROOT_DIR/scripts/okd-nodes.sh" apply

printf '\n%s\n' '------------------------------------------------------------'
printf '%-24s %s\n' 'Jenkins controller' 'READY'
printf '%-24s %s\n' 'Jenkins worker' 'ONLINE'
printf '%-24s %s\n' 'PostgreSQL' 'READY'
printf '%-24s %s\n' 'Edge gateway' 'READY'
printf '%-24s %s\n' 'OKD DNS / LB' 'READY'
printf '%-24s %s\n' 'OKD install prereqs' 'READY'
printf '%-24s %s\n' 'OKD install assets' 'READY'
printf '%-24s %s\n' 'OKD runtime machines' 'BOOTSTRAPPING'
printf '%-24s %s\n' 'Controller FIP' "$JENKINS_FLOATING_IP"
printf '%-24s %s\n' 'Worker FIP' "$JENKINS_WORKER_FLOATING_IP"
printf '%-24s %s\n' 'PostgreSQL FIP' "$POSTGRESQL_FLOATING_IP"
printf '%-24s %s\n' 'okd-lb FIP' "$OKD_LB_FLOATING_IP"
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'LAB CONFIGURATION READY'
