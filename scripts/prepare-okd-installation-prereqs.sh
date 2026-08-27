#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

printf '%s\n' '============================================================'
printf '%s\n' ' OKD installation prerequisites'
printf '%s\n' '============================================================'

printf '[1/2] Preparing pinned openshift-install / oc / kubectl toolchain...\n'
"$ROOT_DIR/scripts/prepare-okd-toolchain.sh"

printf '\n[2/2] Ensuring the matching SCOS boot image exists in Glance...\n'
"$ROOT_DIR/scripts/prepare-okd-image.sh"

printf '\n%s\n' '------------------------------------------------------------'
printf '%-28s %s\n' 'OKD installer toolchain' 'READY'
printf '%-28s %s\n' 'SCOS Glance boot image' 'READY'
printf '%s\n' '------------------------------------------------------------'
printf '%s\n' 'OKD INSTALLATION PREREQUISITES READY'
