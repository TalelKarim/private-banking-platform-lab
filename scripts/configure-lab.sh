#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JENKINS_SERVER_NAME=${JENKINS_SERVER_NAME:-jenkins-controller}
JENKINS_FLOATING_IP=${JENKINS_FLOATING_IP:-}

printf '%s\n' '============================================================'
printf '%s\n' ' Private Banking Platform Lab - Configuration convergence'
printf '%s\n' '============================================================'

if [[ -z "$JENKINS_FLOATING_IP" ]]; then
  printf '[1/3] Discovering Jenkins floating IP from OpenStack...\n'
  JENKINS_FLOATING_IP=$(
    "$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" "$JENKINS_SERVER_NAME"
  )
  printf '      Jenkins floating IP: %s\n' "$JENKINS_FLOATING_IP"
else
  printf '[1/3] Using Jenkins floating IP override: %s\n' "$JENKINS_FLOATING_IP"
fi

printf '[2/3] Converging Jenkins controller with Ansible...\n'
"$ROOT_DIR/scripts/configure-jenkins.sh" "$JENKINS_FLOATING_IP"

printf '[3/3] Converging edge gateway with Ansible...\n'
"$ROOT_DIR/scripts/configure-edge-gateway.sh" "$JENKINS_FLOATING_IP"

printf '\n%s\n' '------------------------------------------------------------'
printf '%-18s %s\n' 'Jenkins' 'READY'
printf '%-18s %s\n' 'Edge gateway' 'READY'
printf '%-18s %s\n' 'Jenkins FIP' "$JENKINS_FLOATING_IP"
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'LAB CONFIGURATION READY'
