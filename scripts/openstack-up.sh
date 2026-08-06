#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

"$ROOT_DIR/scripts/bootstrap-ansible.sh"
"$ROOT_DIR/scripts/kolla.sh" prepare
"$ROOT_DIR/scripts/kolla.sh" deploy
"$ROOT_DIR/scripts/kolla.sh" validate
