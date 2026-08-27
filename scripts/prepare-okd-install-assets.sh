#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OKD_LB_FLOATING_IP=${1:-${OKD_LB_FLOATING_IP:-}}

if [[ -z "$OKD_LB_FLOATING_IP" ]]; then
  echo "Usage: $0 <okd-lb-floating-ip>" >&2
  exit 2
fi

printf '%s\n' '============================================================'
printf '%s\n' ' OKD runtime installation assets'
printf '%s\n' '============================================================'

printf '[1/2] Generating/reusing fresh installer manifests and Ignition...\n'
"$ROOT_DIR/scripts/generate-okd-install-assets.sh"

printf '\n[2/2] Publishing bootstrap/master Ignition to the private okd-lb HTTP endpoint...\n'
"$ROOT_DIR/scripts/publish-okd-ignition.sh" "$OKD_LB_FLOATING_IP"

printf '\n%s\n' '------------------------------------------------------------'
printf '%-30s %s\n' 'OKD install assets' 'READY'
printf '%-30s %s\n' 'Ignition publication' 'READY'
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'OKD RUNTIME INSTALLATION ASSETS READY'
