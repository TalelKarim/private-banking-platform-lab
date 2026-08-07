#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TFVARS_FILE="$ROOT_DIR/infrastructure/terraform/aws/golden.auto.tfvars"

rm -f "$TFVARS_FILE"
echo "Golden mode disabled locally. Terraform will use the stock Ubuntu bootstrap path again."
