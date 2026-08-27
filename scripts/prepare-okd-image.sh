#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}

read_config_value() {
  local key=$1
  awk -F': *' -v wanted="$key" '$1 == wanted {print $2; exit}' "$CLUSTER_CONFIG"
}

OKD_VERSION=${OKD_VERSION:-$(read_config_value okd_release_version)}
OKD_ARCHITECTURE=${OKD_ARCHITECTURE:-$(read_config_value okd_architecture)}
OKD_IMAGE_NAME=${OKD_IMAGE_NAME:-okd-scos-${OKD_VERSION}-${OKD_ARCHITECTURE}}

for binary in aws ssh jq openshift-install; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

if ! openshift-install version | grep -Fq "$OKD_VERSION"; then
  echo "Run scripts/prepare-okd-toolchain.sh first; installer must be $OKD_VERSION" >&2
  exit 1
fi

# Do not hard-code a CoreOS/SCOS build URL. The pinned installer carries the
# stream metadata for the machine OS tested with its own release. Pick the
# OpenStack QCOW2 artifact from that metadata.
STREAM_JSON=$(openshift-install coreos print-stream-json)

IMAGE_METADATA=$(
  jq -r --arg arch "$OKD_ARCHITECTURE" '
    .architectures[$arch].artifacts.openstack.formats as $f
    | if $f["qcow2.gz"] then
        ["qcow2.gz", $f["qcow2.gz"].disk.location, $f["qcow2.gz"].disk.sha256]
      elif $f["qcow2.xz"] then
        ["qcow2.xz", $f["qcow2.xz"].disk.location, $f["qcow2.xz"].disk.sha256]
      elif $f["qcow2"] then
        ["qcow2", $f["qcow2"].disk.location, $f["qcow2"].disk.sha256]
      else
        empty
      end
    | @tsv
  ' <<<"$STREAM_JSON"
)

if [[ -z "$IMAGE_METADATA" ]]; then
  echo "Pinned installer did not expose an OpenStack QCOW2 machine-OS artifact." >&2
  exit 1
fi

IFS=$'\t' read -r IMAGE_FORMAT IMAGE_URL IMAGE_SHA256 <<<"$IMAGE_METADATA"

if [[ ! "$IMAGE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "Invalid machine-OS SHA256 from installer stream metadata: $IMAGE_SHA256" >&2
  exit 1
fi

SSH_KEY=$(mktemp /tmp/private-banking-lab-host-key.XXXXXX)
KNOWN_HOSTS=$(mktemp /tmp/private-banking-lab-host-known-hosts.XXXXXX)
trap 'rm -f "$SSH_KEY" "$KNOWN_HOSTS"' EXIT

aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$LAB_SSH_KEY_PARAMETER" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > "$SSH_KEY"
chmod 0600 "$SSH_KEY"

SSH_OPTS=(
  -i "$SSH_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
)

printf 'Matching machine OS selected by %s:\n' "$OKD_VERSION"
printf '  format : %s\n' "$IMAGE_FORMAT"
printf '  image  : %s\n' "$OKD_IMAGE_NAME"
printf '  source : %s\n' "$IMAGE_URL"

ssh "${SSH_OPTS[@]}" \
  "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
  bash -s -- \
  "$OPENSTACK_CLIENT" \
  "$OPENSTACK_CLOUDS_FILE" \
  "$OPENSTACK_CLOUD" \
  "$OKD_IMAGE_NAME" \
  "$OKD_VERSION" \
  "$IMAGE_FORMAT" \
  "$IMAGE_URL" \
  "$IMAGE_SHA256" <<'REMOTE'
set -euo pipefail

OPENSTACK_CLIENT=$1
OPENSTACK_CLOUDS_FILE=$2
OPENSTACK_CLOUD=$3
IMAGE_NAME=$4
OKD_VERSION=$5
IMAGE_FORMAT=$6
IMAGE_URL=$7
IMAGE_SHA256=$8
CACHE_DIR=/data/images/okd

remote_openstack() {
  env OS_CLIENT_CONFIG_FILE="$OPENSTACK_CLOUDS_FILE" \
    "$OPENSTACK_CLIENT" --os-cloud "$OPENSTACK_CLOUD" "$@"
}

if [[ ! -x "$OPENSTACK_CLIENT" || ! -r "$OPENSTACK_CLOUDS_FILE" ]]; then
  echo "OpenStack client/clouds.yaml unavailable on lab-host." >&2
  exit 1
fi

if remote_openstack image show "$IMAGE_NAME" >/dev/null 2>&1; then
  existing_status=$(remote_openstack image show "$IMAGE_NAME" -f value -c status)
  if [[ "$existing_status" == "active" ]]; then
    echo "Glance image already exists and is active: $IMAGE_NAME"
    remote_openstack image show "$IMAGE_NAME" -f yaml -c id -c name -c status -c disk_format -c size
    exit 0
  fi

  echo "Removing stale Glance image $IMAGE_NAME (status=$existing_status) before retry..."
  remote_openstack image delete "$IMAGE_NAME"
fi

for binary in curl python3 sha256sum; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required lab-host command not found: $binary" >&2
    exit 1
  }
done

sudo install -d -m 0755 -o "$USER" -g "$(id -gn)" "$CACHE_DIR"
DOWNLOAD="$CACHE_DIR/${IMAGE_NAME}.${IMAGE_FORMAT}"
QCOW2="$CACHE_DIR/${IMAGE_NAME}.qcow2"

rm -f "$DOWNLOAD" "$QCOW2"

echo "Downloading matching SCOS/OpenStack artifact on lab-host..."
curl -fL --retry 3 --retry-delay 3 -o "$DOWNLOAD" "$IMAGE_URL"
printf '%s  %s\n' "$IMAGE_SHA256" "$DOWNLOAD" | sha256sum -c -

python3 - "$IMAGE_FORMAT" "$DOWNLOAD" "$QCOW2" <<'PY'
import gzip
import lzma
import shutil
import sys

fmt, source, target = sys.argv[1:]
if fmt == "qcow2.gz":
    opener = gzip.open
elif fmt == "qcow2.xz":
    opener = lzma.open
elif fmt == "qcow2":
    shutil.copyfile(source, target)
    raise SystemExit(0)
else:
    raise SystemExit(f"Unsupported format: {fmt}")

with opener(source, "rb") as src, open(target, "wb") as dst:
    shutil.copyfileobj(src, dst, length=16 * 1024 * 1024)
PY

[[ -s "$QCOW2" ]] || {
  echo "Decompressed QCOW2 is empty: $QCOW2" >&2
  exit 1
}

echo "Uploading matching machine OS to Glance as $IMAGE_NAME..."
remote_openstack image create \
  --container-format bare \
  --disk-format qcow2 \
  --private \
  --file "$QCOW2" \
  --property managed_by=private-banking-platform-lab \
  --property okd_release="$OKD_VERSION" \
  "$IMAGE_NAME" >/dev/null

for attempt in $(seq 1 60); do
  status=$(remote_openstack image show "$IMAGE_NAME" -f value -c status 2>/dev/null || true)
  [[ "$status" == "active" ]] && break
  [[ "$status" == "killed" || "$status" == "deleted" ]] && {
    echo "Glance image entered unexpected status: $status" >&2
    exit 1
  }
  sleep 2
done

status=$(remote_openstack image show "$IMAGE_NAME" -f value -c status)
if [[ "$status" != "active" ]]; then
  echo "Glance image did not become active: $IMAGE_NAME (status=$status)" >&2
  exit 1
fi

rm -f "$DOWNLOAD" "$QCOW2"
remote_openstack image show "$IMAGE_NAME" -f yaml -c id -c name -c status -c disk_format -c size
REMOTE

printf '\nOKD machine OS is READY in Glance: %s\n' "$OKD_IMAGE_NAME"
