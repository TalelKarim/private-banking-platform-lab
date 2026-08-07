#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
AMI_NAME=${AMI_NAME:-private-banking-platform-lab-openstack-$(date -u +%Y%m%d-%H%M%S)}

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

INSTANCE_ID=$(terraform -chdir="$TF_DIR" output -raw instance_id)
REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
EXPECTED_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw configured_openstack_host_private_ip)
GOLDEN_MODE=$(terraform -chdir="$TF_DIR" output -raw golden_ami_mode)

if [ "$GOLDEN_MODE" = "true" ]; then
  echo "Terraform is already in Golden AMI mode. Refusing to bake over the runtime host." >&2
  echo "Deactivate Golden mode first if you intentionally want to rebuild the baseline." >&2
  exit 1
fi

ACTUAL_PRIVATE_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

if [ "$ACTUAL_PRIVATE_IP" != "$EXPECTED_PRIVATE_IP" ]; then
  echo "Private IP mismatch: instance=$ACTUAL_PRIVATE_IP expected=$EXPECTED_PRIVATE_IP" >&2
  echo "Do not bake: Kolla endpoints must match the stable Terraform private IP." >&2
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
if [ "$DEVICE_COUNT" -ne 3 ]; then
  echo "Expected exactly 3 EBS block devices (root, /data, Cinder); found $DEVICE_COUNT:" >&2
  printf '  %s\n' "$@" >&2
  exit 1
fi

# Preserve all three source EBS volumes in the AMI and force their clones to
# be deleted when a Golden-AMI runtime instance is terminated.
MAPPINGS="["
SEP=""
for DEVICE in "$@"; do
  MAPPINGS="${MAPPINGS}${SEP}{\"DeviceName\":\"${DEVICE}\",\"Ebs\":{\"DeleteOnTermination\":true}}"
  SEP=","
done
MAPPINGS="${MAPPINGS}]"

WAS_RUNNING=false
if [ "$STATE" = "running" ]; then
  WAS_RUNNING=true
  echo "Stopping $INSTANCE_ID so the three EBS snapshots are filesystem-consistent..."
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

echo "Creating AMI '$AMI_NAME' from $INSTANCE_ID..."
AMI_ID=$(aws ec2 create-image \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "OpenStack Kolla all-in-one Golden AMI for private-banking-platform-lab" \
  --no-reboot \
  --block-device-mappings "$MAPPINGS" \
  --tag-specifications \
    "ResourceType=image,Tags=[{Key=Name,Value=$AMI_NAME},{Key=Project,Value=private-banking-platform-lab},{Key=Role,Value=OpenStack-Golden-AMI}]" \
    "ResourceType=snapshot,Tags=[{Key=Project,Value=private-banking-platform-lab},{Key=Role,Value=OpenStack-Golden-AMI}]" \
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

if [ "$SNAPSHOT_COUNT" -ne 3 ]; then
  echo "AMI $AMI_ID is available but contains $SNAPSHOT_COUNT EBS snapshots instead of 3." >&2
  exit 1
fi

echo
echo "Golden AMI AVAILABLE: $AMI_ID"
aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].BlockDeviceMappings[].{Device:DeviceName,Snapshot:Ebs.SnapshotId,DeleteOnTermination:Ebs.DeleteOnTermination}' \
  --output table

echo
echo "Next step on the Mac:"
echo "  make activate-golden-ami AMI_ID=$AMI_ID"
echo "Then run:"
echo "  cd infrastructure/terraform/aws && terraform plan"
