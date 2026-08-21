#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
REGION=${AWS_REGION:-eu-south-2}

LAB_INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
EDGE_INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_instance_id)

aws ec2 start-instances \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" "$EDGE_INSTANCE_ID" \
  >/dev/null

aws ec2 wait instance-running \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" "$EDGE_INSTANCE_ID"

aws ec2 wait instance-status-ok \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" "$EDGE_INSTANCE_ID"

LAB_PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$LAB_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

EDGE_PUBLIC_IP=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_public_ip)

printf 'lab-host public IP: %s\n' "$LAB_PUBLIC_IP"
printf 'edge-gateway EIP : %s\n' "$EDGE_PUBLIC_IP"
