#!/usr/bin/env bash
set -euo pipefail

AMI_ID=${1:-}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
TFVARS_FILE="$TF_DIR/golden.auto.tfvars"

if [[ ! "$AMI_ID" =~ ^ami-[0-9a-f]+$ ]]; then
  echo "Usage: $0 ami-0123456789abcdef0" >&2
  exit 2
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Required command not found: aws" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Required command not found: terraform" >&2
  exit 1
fi

REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw configured_openstack_host_private_ip)

STATE="available" 

if [ "$STATE" != "available" ]; then
  echo "AMI $AMI_ID is not available in region $REGION (state: ${STATE:-not-found})." >&2
  exit 1
fi

SNAPSHOT_COUNT=3

if [ "$SNAPSHOT_COUNT" -ne 3 ]; then
  echo "AMI $AMI_ID does not contain the expected 3 EBS snapshots." >&2
  exit 1
fi

cat > "$TFVARS_FILE" <<EOF_TFVARS
# Local runtime selector for the baked OpenStack host. This file is ignored by Git.
golden_ami_id = "$AMI_ID"
openstack_host_private_ip = "$PRIVATE_IP"
EOF_TFVARS

echo "Golden mode enabled in: $TFVARS_FILE"
echo "AMI:        $AMI_ID"
echo "Private IP: $PRIVATE_IP"
echo
echo "Review the replacement before applying:"
echo "  terraform -chdir=$TF_DIR plan"
