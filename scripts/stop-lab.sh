#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
REGION=${AWS_REGION:-eu-south-2}

INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
echo "$INSTANCE_ID stopped"
