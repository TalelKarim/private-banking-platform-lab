#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
REGION=${AWS_REGION:-eu-south-2}

LAB_INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
EDGE_INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_instance_id)

aws ec2 stop-instances \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" "$EDGE_INSTANCE_ID" \
  >/dev/null

aws ec2 wait instance-stopped \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" "$EDGE_INSTANCE_ID"

printf '%s stopped (lab-host)\n' "$LAB_INSTANCE_ID"
printf '%s stopped (edge-gateway)\n' "$EDGE_INSTANCE_ID"
