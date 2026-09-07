#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
AMI_NAME=${AMI_NAME:-private-banking-platform-lab-edge-gateway-ready-$(date -u +%Y%m%d-%H%M%S)}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_cmd aws
require_cmd terraform

if [ ! -d "$TF_DIR/.terraform" ]; then
  echo "Terraform is not initialized in $TF_DIR. Run terraform init first." >&2
  exit 1
fi

INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_instance_id)
REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
EXPECTED_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_private_ip)

ACTUAL_PRIVATE_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

if [ "$ACTUAL_PRIVATE_IP" != "$EXPECTED_PRIVATE_IP" ]; then
  echo "Private IP mismatch: edge=$ACTUAL_PRIVATE_IP expected=$EXPECTED_PRIVATE_IP" >&2
  echo "Do not bake: the edge gateway must keep its stable Terraform private IP." >&2
  exit 1
fi

STATE=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

DEVICE_NAMES=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[].DeviceName' \
  --output text)

set -- $DEVICE_NAMES
DEVICE_COUNT=$#
if [ "$DEVICE_COUNT" -ne 1 ]; then
  echo "Expected exactly 1 EBS block device for the edge gateway root disk; found $DEVICE_COUNT:" >&2
  printf '  %s\n' "$@" >&2
  exit 1
fi

ROOT_DEVICE="$1"
MAPPINGS="[{\"DeviceName\":\"${ROOT_DEVICE}\",\"Ebs\":{\"DeleteOnTermination\":true}}]"

WAS_RUNNING=false
if [ "$STATE" = "running" ]; then
  WAS_RUNNING=true
  echo "Stopping $INSTANCE_ID before creating the edge gateway AMI..."
  aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
  aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$INSTANCE_ID"
elif [ "$STATE" != "stopped" ]; then
  echo "Instance must be running or stopped before baking; current state: $STATE" >&2
  exit 1
fi

cleanup() {
  rc=$?
  if [ "$WAS_RUNNING" = true ]; then
    current_state=$(aws ec2 describe-instances \
      --region "$REGION" \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' \
      --output text 2>/dev/null || true)
    if [ "$current_state" = "stopped" ]; then
      echo "Restarting source instance $INSTANCE_ID..."
      aws ec2 start-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null || true
    fi
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

echo "Creating edge gateway AMI '$AMI_NAME' from $INSTANCE_ID..."
AMI_ID=$(aws ec2 create-image \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "Ready edge gateway checkpoint for private-banking-platform-lab" \
  --no-reboot \
  --block-device-mappings "$MAPPINGS" \
  --tag-specifications \
    "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=private-banking-platform-lab},{Key=Role,Value=Edge-Gateway-Ready-AMI}]" \
    "ResourceType=snapshot,Tags=[{Key=Project,Value=private-banking-platform-lab},{Key=Role,Value=Edge-Gateway-Ready-AMI}]" \
  --query ImageId \
  --output text)

echo "AMI requested: $AMI_ID"
echo "Waiting until it is available..."
aws ec2 wait image-available --region "$REGION" --image-ids "$AMI_ID"

SNAPSHOT_COUNT=$(aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$AMI_ID" \
  --query 'length(Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=`null`])' \
  --output text)

if [ "$SNAPSHOT_COUNT" -ne 1 ]; then
  echo "AMI $AMI_ID is available but contains $SNAPSHOT_COUNT EBS snapshots instead of 1." >&2
  exit 1
fi

echo
echo "EDGE GATEWAY READY AMI AVAILABLE: $AMI_ID"
aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].BlockDeviceMappings[].{Device:DeviceName,Snapshot:Ebs.SnapshotId,DeleteOnTermination:Ebs.DeleteOnTermination}' \
  --output table

echo
echo "Next step after baking the lab-host AMI:"
echo "  make activate-ready-amis LAB_HOST_AMI_ID=ami-... EDGE_GATEWAY_AMI_ID=$AMI_ID"
