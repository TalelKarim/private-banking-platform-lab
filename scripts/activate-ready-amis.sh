#!/usr/bin/env bash
set -euo pipefail

LAB_HOST_AMI_ID=${LAB_HOST_AMI_ID:-${1:-}}
EDGE_GATEWAY_AMI_ID=${EDGE_GATEWAY_AMI_ID:-${2:-}}
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/infrastructure/terraform/aws"
TFVARS_FILE="$TF_DIR/ready.auto.tfvars"

if [[ ! "$LAB_HOST_AMI_ID" =~ ^ami-[0-9a-f]+$ ]]; then
  echo "Usage: LAB_HOST_AMI_ID=ami-... EDGE_GATEWAY_AMI_ID=ami-... $0" >&2
  exit 2
fi

if [[ ! "$EDGE_GATEWAY_AMI_ID" =~ ^ami-[0-9a-f]+$ ]]; then
  echo "Usage: LAB_HOST_AMI_ID=ami-... EDGE_GATEWAY_AMI_ID=ami-... $0" >&2
  exit 2
fi

for binary in aws terraform; do
  command -v "$binary" >/dev/null 2>&1 || { echo "Required command not found: $binary" >&2; exit 1; }
done

REGION=$(terraform -chdir="$TF_DIR" output -raw aws_region)
OPENSTACK_HOST_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw configured_openstack_host_private_ip)
EDGE_GATEWAY_PRIVATE_IP=$(terraform -chdir="$TF_DIR" output -raw edge_gateway_private_ip)

LAB_STATE=$(aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$LAB_HOST_AMI_ID" \
  --query 'Images[0].State' \
  --output text)

EDGE_STATE=$(aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$EDGE_GATEWAY_AMI_ID" \
  --query 'Images[0].State' \
  --output text)

if [ "$LAB_STATE" != "available" ]; then
  echo "Lab-host AMI $LAB_HOST_AMI_ID is not available in $REGION (state: $LAB_STATE)." >&2
  exit 1
fi

if [ "$EDGE_STATE" != "available" ]; then
  echo "Edge gateway AMI $EDGE_GATEWAY_AMI_ID is not available in $REGION (state: $EDGE_STATE)." >&2
  exit 1
fi

LAB_SNAPSHOT_COUNT=$(aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$LAB_HOST_AMI_ID" \
  --query 'length(Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=`null`])' \
  --output text)

EDGE_SNAPSHOT_COUNT=$(aws ec2 describe-images \
  --region "$REGION" \
  --image-ids "$EDGE_GATEWAY_AMI_ID" \
  --query 'length(Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=`null`])' \
  --output text)

if [ "$LAB_SNAPSHOT_COUNT" -ne 3 ]; then
  echo "Lab-host AMI $LAB_HOST_AMI_ID must contain root + /data + Cinder snapshots; found $LAB_SNAPSHOT_COUNT." >&2
  exit 1
fi

if [ "$EDGE_SNAPSHOT_COUNT" -ne 1 ]; then
  echo "Edge gateway AMI $EDGE_GATEWAY_AMI_ID must contain exactly one root snapshot; found $EDGE_SNAPSHOT_COUNT." >&2
  exit 1
fi

cat > "$TFVARS_FILE" <<EOF_TFVARS
# Local runtime selector for the ready lab checkpoint. This file is ignored by Git.
# lab-host AMI contains root + /data + Cinder EBS snapshots.
golden_ami_id = "$LAB_HOST_AMI_ID"

# edge-gateway AMI contains the configured Nginx/root disk snapshot.
edge_gateway_ami_id = "$EDGE_GATEWAY_AMI_ID"

# Keep the baked control-plane and edge addresses stable.
openstack_host_private_ip = "$OPENSTACK_HOST_PRIVATE_IP"
edge_gateway_private_ip   = "$EDGE_GATEWAY_PRIVATE_IP"
EOF_TFVARS

echo "Ready AMI mode enabled in: $TFVARS_FILE"
echo "Lab-host AMI:      $LAB_HOST_AMI_ID"
echo "Edge-gateway AMI:  $EDGE_GATEWAY_AMI_ID"
echo "OpenStack host IP: $OPENSTACK_HOST_PRIVATE_IP"
echo "Edge gateway IP:   $EDGE_GATEWAY_PRIVATE_IP"
echo
echo "Review before applying:"
echo "  terraform -chdir=$TF_DIR plan"
