#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ACTION=${1:-status}
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
TF_DIR="$ROOT_DIR/platform/openshift/terraform/runtime-nodes"
RUNTIME_ROOT=${OKD_RUNTIME_ROOT:-$ROOT_DIR/.runtime/openshift}
INSTALL_DIR="$RUNTIME_ROOT/install"
STUB_DIR="$RUNTIME_ROOT/ignition-stubs"
TF_RUNTIME_DIR="$RUNTIME_ROOT/terraform-nodes"
TF_DATA_DIR="$TF_RUNTIME_DIR/.terraform"
TF_STATE="$TF_RUNTIME_DIR/terraform.tfstate"
TF_VARS="$TF_RUNTIME_DIR/runtime.auto.tfvars.json"
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}

AWS_REGION=${AWS_REGION:-eu-south-2}
LAB_HOST_PRIVATE_IP=${LAB_HOST_PRIVATE_IP:-172.31.31.70}
LAB_HOST_SSH_USER=${LAB_HOST_SSH_USER:-ubuntu}
LAB_SSH_KEY_PARAMETER=${LAB_SSH_KEY_PARAMETER:-/private-banking-platform-lab/aws/lab-ssh-private-key}
OPENSTACK_CLIENT=${OPENSTACK_CLIENT:-/opt/openstack-client-venv/bin/openstack}
OPENSTACK_CLOUDS_FILE=${OPENSTACK_CLOUDS_FILE:-/data/openstack/secrets/clouds.yaml}
OPENSTACK_CLOUD=${OPENSTACK_CLOUD:-kolla-admin}
WORKLOAD_KEY=${WORKLOAD_SSH_PRIVATE_KEY:-/home/ubuntu/.ssh/private-banking-openstack-workloads}
IGNITION_FETCH_ATTEMPTS=${IGNITION_FETCH_ATTEMPTS:-60}
IGNITION_FETCH_INTERVAL_SECONDS=${IGNITION_FETCH_INTERVAL_SECONDS:-5}

usage() {
  cat <<'EOF_USAGE'
Usage: scripts/okd-nodes.sh <apply|status|retire-bootstrap|destroy|console> [node]

  apply             Generate verified Ignition stubs and converge the runtime OKD machines
  status            Show bootstrap (if present) and the three control planes
  retire-bootstrap  Remove only the temporary bootstrap VM/port from runtime Terraform
  destroy           Destroy the complete runtime OKD Terraform layer
  console           Show recent Nova console output for bootstrap, okd-01, okd-02 or okd-03
EOF_USAGE
}

case "$ACTION" in
  apply|status|retire-bootstrap|destroy|console) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for binary in aws ssh terraform jq sha256sum; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

if [[ ! -x "$ANSIBLE_PYTHON" ]]; then
  echo "Python from the Ansible control environment is required: $ANSIBLE_PYTHON" >&2
  exit 1
fi

# Read the canonical cluster topology once. JSON avoids fragile shell parsing of
# the nested bootstrap/control-plane arrays.
CONFIG_JSON=$(
  "$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import json
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = yaml.safe_load(handle)

required = [
    "okd_release_version",
    "okd_architecture",
    "okd_lb_ip",
    "okd_ignition_http_port",
    "okd_bootstrap",
    "okd_control_planes",
    "okd_openstack_network_name",
    "okd_openstack_subnet_name",
    "okd_openstack_flavor_name",
    "okd_openstack_security_group_name",
    "okd_openstack_keypair_name",
]
missing = [key for key in required if key not in cfg]
if missing:
    raise SystemExit("Missing OKD config keys: " + ", ".join(missing))

if len(cfg["okd_control_planes"]) != 3:
    raise SystemExit("The compact cluster must define exactly three control planes")

print(json.dumps(cfg))
PY
)

OKD_VERSION=$(jq -r '.okd_release_version' <<<"$CONFIG_JSON")
OKD_ARCHITECTURE=$(jq -r '.okd_architecture' <<<"$CONFIG_JSON")
OKD_LB_IP=$(jq -r '.okd_lb_ip' <<<"$CONFIG_JSON")
OKD_IGNITION_HTTP_PORT=$(jq -r '.okd_ignition_http_port' <<<"$CONFIG_JSON")
OKD_IMAGE_NAME="okd-scos-${OKD_VERSION}-${OKD_ARCHITECTURE}"
OPENSTACK_NETWORK_NAME=$(jq -r '.okd_openstack_network_name' <<<"$CONFIG_JSON")
OPENSTACK_SUBNET_NAME=$(jq -r '.okd_openstack_subnet_name' <<<"$CONFIG_JSON")
OPENSTACK_FLAVOR_NAME=$(jq -r '.okd_openstack_flavor_name' <<<"$CONFIG_JSON")
OPENSTACK_SECURITY_GROUP_NAME=$(jq -r '.okd_openstack_security_group_name' <<<"$CONFIG_JSON")
OPENSTACK_KEYPAIR_NAME=$(jq -r '.okd_openstack_keypair_name' <<<"$CONFIG_JSON")
BOOTSTRAP_NAME=$(jq -r '.okd_bootstrap.name' <<<"$CONFIG_JSON")
BOOTSTRAP_IP=$(jq -r '.okd_bootstrap.ip' <<<"$CONFIG_JSON")
mapfile -t CONTROL_PLANE_NAMES < <(jq -r '.okd_control_planes[].name' <<<"$CONFIG_JSON")

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

remote_openstack() {
  local remote_cmd
  printf -v remote_cmd '%q ' \
    env "OS_CLIENT_CONFIG_FILE=$OPENSTACK_CLOUDS_FILE" \
    "$OPENSTACK_CLIENT" \
    --os-cloud "$OPENSTACK_CLOUD" \
    "$@"

  ssh "${SSH_OPTS[@]}" \
    "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
    "$remote_cmd"
}

if ! ssh "${SSH_OPTS[@]}" \
  "${LAB_HOST_SSH_USER}@${LAB_HOST_PRIVATE_IP}" \
  "test -x '$OPENSTACK_CLIENT' && test -r '$OPENSTACK_CLOUDS_FILE'"; then
  echo "OpenStack client/clouds.yaml unavailable on lab-host $LAB_HOST_PRIVATE_IP." >&2
  exit 1
fi

if ! remote_openstack token issue -f value -c id >/dev/null; then
  echo "OpenStack authentication on lab-host failed." >&2
  exit 1
fi

show_status() {
  printf '%-14s %-10s %-16s %s\n' NAME STATUS FIXED_IP IMAGE
  printf '%-14s %-10s %-16s %s\n' '--------------' '----------' '----------------' '-----'

  local name status addresses image ip
  for name in "$BOOTSTRAP_NAME" "${CONTROL_PLANE_NAMES[@]}"; do
    if ! status=$(remote_openstack server show "$name" -f value -c status 2>/dev/null); then
      printf '%-14s %-10s %-16s %s\n' "$name" MISSING '-' '-'
      continue
    fi
    addresses=$(remote_openstack server show "$name" -f value -c addresses)
    image=$(remote_openstack server show "$name" -f value -c image 2>/dev/null || true)
    ip=$(grep -oE '10\.20\.0\.[0-9]+' <<<"$addresses" | head -n1 || true)
    printf '%-14s %-10s %-16s %s\n' "$name" "$status" "${ip:--}" "${image:--}"
  done
}

if [[ "$ACTION" == status ]]; then
  show_status
  exit 0
fi

if [[ "$ACTION" == console ]]; then
  NODE=${2:-$BOOTSTRAP_NAME}
  case "$NODE" in
    "$BOOTSTRAP_NAME"|"${CONTROL_PLANE_NAMES[0]}"|"${CONTROL_PLANE_NAMES[1]}"|"${CONTROL_PLANE_NAMES[2]}") ;;
    *) echo "Unknown OKD node: $NODE" >&2; exit 2 ;;
  esac
  remote_openstack console log show --lines 160 "$NODE"
  exit 0
fi

# Terraform runs locally on ops-runner only for this short-lived runtime layer.
# Permanent OpenStack credentials remain on lab-host: we mint a short-lived,
# project-scoped Keystone token and export it only to this Terraform process.
TOKEN_JSON=$(remote_openstack token issue -f json -c id -c project_id)
OS_TOKEN_VALUE=$(jq -r '.id' <<<"$TOKEN_JSON")
OS_PROJECT_ID_VALUE=$(jq -r '.project_id' <<<"$TOKEN_JSON")
OS_AUTH_URL_VALUE=$(remote_openstack endpoint list --service identity --interface public -f value -c URL | head -n1)
OS_REGION_NAME_VALUE=$(remote_openstack endpoint list --interface public -f value -c Region | awk 'NF {print; exit}')
OS_REGION_NAME_VALUE=${OS_REGION_NAME_VALUE:-RegionOne}

if [[ -z "$OS_TOKEN_VALUE" || "$OS_TOKEN_VALUE" == null || -z "$OS_PROJECT_ID_VALUE" || "$OS_PROJECT_ID_VALUE" == null || -z "$OS_AUTH_URL_VALUE" ]]; then
  echo "Unable to derive temporary OpenStack token authentication for runtime Terraform." >&2
  exit 1
fi

export OS_AUTH_URL="$OS_AUTH_URL_VALUE"
export OS_TOKEN="$OS_TOKEN_VALUE"
export OS_PROJECT_ID="$OS_PROJECT_ID_VALUE"
export OS_REGION_NAME="$OS_REGION_NAME_VALUE"
export OS_IDENTITY_API_VERSION=3
export OS_ALLOW_REAUTH=false
export TF_IN_AUTOMATION=1
export TF_DATA_DIR

mkdir -p "$TF_RUNTIME_DIR"
chmod 0700 "$TF_RUNTIME_DIR"

if [[ "$ACTION" == retire-bootstrap ]]; then
  if [[ ! -s "$TF_STATE" || ! -s "$TF_VARS" ]]; then
    if ! remote_openstack server show "$BOOTSTRAP_NAME" >/dev/null 2>&1; then
      echo "Bootstrap is already absent and no runtime Terraform state needs convergence."
      exit 0
    fi
    echo "Runtime Terraform state/variables are missing while bootstrap still exists." >&2
    echo "Refusing an unmanaged Nova deletion; recover the runtime state first." >&2
    exit 1
  fi

  tmp_vars=$(mktemp "$TF_RUNTIME_DIR/runtime.auto.tfvars.json.XXXXXX")
  jq '.bootstrap_enabled = false' "$TF_VARS" > "$tmp_vars"
  chmod 0600 "$tmp_vars"
  mv "$tmp_vars" "$TF_VARS"

  printf 'Retiring bootstrap through the existing runtime Terraform state...\n'
  terraform -chdir="$TF_DIR" init -input=false >/dev/null
  terraform -chdir="$TF_DIR" apply \
    -input=false \
    -auto-approve \
    -state="$TF_STATE" \
    -var-file="$TF_VARS"

  if remote_openstack server show "$BOOTSTRAP_NAME" >/dev/null 2>&1; then
    echo "Bootstrap Nova server still exists after Terraform convergence: $BOOTSTRAP_NAME" >&2
    exit 1
  fi

  printf '\nBootstrap runtime resources retired; control-plane Terraform resources are preserved.\n'
  show_status
  exit 0
fi

if [[ "$ACTION" == destroy ]]; then
  if [[ ! -s "$TF_STATE" || ! -s "$TF_VARS" ]]; then
    echo "Runtime Terraform state/variables are absent; nothing managed locally to destroy." >&2
    echo "If Nova servers still exist, inspect them with: make status-okd-nodes" >&2
    exit 0
  fi

  if [[ "${SKIP_OPENSHIFT_STORAGE_CLEANUP:-false}" != "true" ]]; then
    "$ROOT_DIR/scripts/cleanup-openshift-storage.sh"
  fi

  terraform -chdir="$TF_DIR" init -input=false >/dev/null
  terraform -chdir="$TF_DIR" destroy \
    -input=false \
    -auto-approve \
    -state="$TF_STATE" \
    -var-file="$TF_VARS"

  rm -f "$TF_STATE" "$TF_STATE.backup" "$TF_VARS"
  printf '\nRuntime OKD bootstrap/control-plane machines destroyed.\n'
  exit 0
fi

# ACTION=apply from here.
for required in \
  "$INSTALL_DIR/bootstrap.ign" \
  "$INSTALL_DIR/master.ign" \
  "$INSTALL_DIR/auth/kubeconfig"; do
  [[ -s "$required" ]] || {
    echo "Missing fresh installer asset: $required" >&2
    echo "Run make prepare-okd-install-assets first." >&2
    exit 1
  }
done

if [[ ! -r "$WORKLOAD_KEY" ]]; then
  echo "Missing OpenStack workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

mkdir -p "$STUB_DIR"
chmod 0700 "$STUB_DIR"

make_stub() {
  local source=$1
  local url=$2
  local hostname=$3
  local destination=$4

  "$ANSIBLE_PYTHON" - "$source" "$url" "$hostname" "$destination" <<'PY'
import base64
import hashlib
import json
import sys
from pathlib import Path

source_path, source_url, hostname, destination = sys.argv[1:]
raw = Path(source_path).read_bytes()
source = json.loads(raw)
version = source.get("ignition", {}).get("version")
if not version:
    raise SystemExit(f"Ignition version missing from {source_path}")

sha256 = hashlib.sha256(raw).hexdigest()
hostname_data = base64.b64encode((hostname + "\n").encode()).decode()

# Keep userdata tiny. The node-specific stub sets a deterministic hostname and
# merges the large installer-generated payload from okd-lb. The SHA-256 binds
# the HTTP fetch to the exact runtime asset generated by openshift-install.
stub = {
    "ignition": {
        "version": version,
        "config": {
            "merge": [
                {
                    "source": source_url,
                    "verification": {"hash": "sha256-" + sha256},
                }
            ]
        },
    },
    "storage": {
        "files": [
            {
                "path": "/etc/hostname",
                "mode": 420,
                "overwrite": True,
                "contents": {
                    "source": "data:text/plain;charset=utf-8;base64," + hostname_data
                },
            }
        ]
    },
}

Path(destination).write_text(json.dumps(stub, separators=(",", ":")) + "\n", encoding="utf-8")
PY
  chmod 0600 "$destination"
  jq -e '.ignition.version and .ignition.config.merge[0].source and .ignition.config.merge[0].verification.hash' "$destination" >/dev/null
}

printf 'Generating verified node-specific Ignition stubs...\n'
make_stub \
  "$INSTALL_DIR/bootstrap.ign" \
  "http://$OKD_LB_IP:$OKD_IGNITION_HTTP_PORT/bootstrap.ign" \
  "$BOOTSTRAP_NAME" \
  "$STUB_DIR/$BOOTSTRAP_NAME.ign"

for name in "${CONTROL_PLANE_NAMES[@]}"; do
  make_stub \
    "$INSTALL_DIR/master.ign" \
    "http://$OKD_LB_IP:$OKD_IGNITION_HTTP_PORT/master.ign" \
    "$name" \
    "$STUB_DIR/$name.ign"
done

printf 'Resolving existing OpenStack foundation IDs on lab-host...\n'
NETWORK_ID=$(remote_openstack network show "$OPENSTACK_NETWORK_NAME" -f value -c id)
SUBNET_ID=$(remote_openstack subnet show "$OPENSTACK_SUBNET_NAME" -f value -c id)
FLAVOR_ID=$(remote_openstack flavor show "$OPENSTACK_FLAVOR_NAME" -f value -c id)
SECURITY_GROUP_ID=$(remote_openstack security group show "$OPENSTACK_SECURITY_GROUP_NAME" -f value -c id)
IMAGE_ID=$(remote_openstack image show "$OKD_IMAGE_NAME" -f value -c id)
IMAGE_STATUS=$(remote_openstack image show "$OKD_IMAGE_NAME" -f value -c status)
remote_openstack keypair show "$OPENSTACK_KEYPAIR_NAME" >/dev/null

if [[ "$IMAGE_STATUS" != active ]]; then
  echo "SCOS Glance image is not active: $OKD_IMAGE_NAME (status=$IMAGE_STATUS)" >&2
  exit 1
fi

export CONFIG_JSON NETWORK_ID SUBNET_ID FLAVOR_ID SECURITY_GROUP_ID IMAGE_ID OPENSTACK_KEYPAIR_NAME
export BOOTSTRAP_NAME BOOTSTRAP_IP STUB_DIR TF_VARS
"$ANSIBLE_PYTHON" <<'PY'
import json
import os
from pathlib import Path

cfg = json.loads(os.environ["CONFIG_JSON"])
stub_dir = Path(os.environ["STUB_DIR"])

tfvars_path = Path(os.environ["TF_VARS"])
bootstrap_enabled = True
if tfvars_path.exists():
    try:
        previous = json.loads(tfvars_path.read_text(encoding="utf-8"))
        bootstrap_enabled = bool(previous.get("bootstrap_enabled", True))
    except (OSError, ValueError, TypeError):
        bootstrap_enabled = True

data = {
    "bootstrap_enabled": bootstrap_enabled,
    "network_id": os.environ["NETWORK_ID"],
    "subnet_id": os.environ["SUBNET_ID"],
    "security_group_id": os.environ["SECURITY_GROUP_ID"],
    "image_id": os.environ["IMAGE_ID"],
    "flavor_id": os.environ["FLAVOR_ID"],
    "key_pair": os.environ["OPENSTACK_KEYPAIR_NAME"],
    "bootstrap": {
        "name": os.environ["BOOTSTRAP_NAME"],
        "ip": os.environ["BOOTSTRAP_IP"],
        "ignition_path": str(stub_dir / f"{os.environ['BOOTSTRAP_NAME']}.ign"),
    },
    "control_planes": {
        node["name"]: {
            "ip": node["ip"],
            "ignition_path": str(stub_dir / f"{node['name']}.ign"),
        }
        for node in cfg["okd_control_planes"]
    },
}

tfvars_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
chmod 0600 "$TF_VARS"
BOOTSTRAP_ENABLED=$(jq -r 'if has("bootstrap_enabled") then .bootstrap_enabled else true end' "$TF_VARS")

printf '\nConverging runtime OKD machines with Terraform (bootstrap_enabled=%s)...\n' "$BOOTSTRAP_ENABLED"
terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" apply \
  -input=false \
  -auto-approve \
  -state="$TF_STATE" \
  -var-file="$TF_VARS"

RUNTIME_NODE_NAMES=("${CONTROL_PLANE_NAMES[@]}")
if [[ "$BOOTSTRAP_ENABLED" == true ]]; then
  RUNTIME_NODE_NAMES=("$BOOTSTRAP_NAME" "${RUNTIME_NODE_NAMES[@]}")
fi

printf '\nWaiting for managed SCOS machines to become ACTIVE in Nova...\n'
for attempt in $(seq 1 60); do
  all_active=true
  for name in "${RUNTIME_NODE_NAMES[@]}"; do
    status=$(remote_openstack server show "$name" -f value -c status 2>/dev/null || true)
    [[ "$status" == ACTIVE ]] || all_active=false
  done
  [[ "$all_active" == true ]] && break
  sleep 5
done

for name in "${RUNTIME_NODE_NAMES[@]}"; do
  status=$(remote_openstack server show "$name" -f value -c status 2>/dev/null || true)
  if [[ "$status" != ACTIVE ]]; then
    echo "Nova server did not become ACTIVE: $name (status=${status:-missing})" >&2
    exit 1
  fi
done

show_status

# Prove the end-to-end first-boot handoff: config-drive -> Ignition stub ->
# node network -> Nginx -> verified bootstrap/master payload.
OKD_LB_FLOATING_IP=$("$ROOT_DIR/scripts/discover-openstack-floating-ip.sh" okd-lb)
LB_SSH_OPTS=(
  -i "$WORKLOAD_KEY"
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o StrictHostKeyChecking=accept-new
)
LB_REMOTE="ubuntu@$OKD_LB_FLOATING_IP"

printf '\nWaiting for all SCOS nodes to fetch their real Ignition payloads from okd-lb...\n'
fetch_seen() {
  local source_ip=$1
  local uri=$2
  ssh "${LB_SSH_OPTS[@]}" "$LB_REMOTE" \
    "sudo awk -v ip='$source_ip' -v uri='$uri' '\$1 == ip && \$7 == uri && \$9 == 200 {found=1} END {exit(found ? 0 : 1)}' /var/log/nginx/okd-ignition-access.log" \
    >/dev/null 2>&1
}

for attempt in $(seq 1 "$IGNITION_FETCH_ATTEMPTS"); do
  all_fetched=true
  if [[ "$BOOTSTRAP_ENABLED" == true ]]; then
    fetch_seen "$BOOTSTRAP_IP" /bootstrap.ign || all_fetched=false
  fi
  while IFS=$'\t' read -r name ip; do
    fetch_seen "$ip" /master.ign || all_fetched=false
  done < <(jq -r '.okd_control_planes[] | [.name, .ip] | @tsv' <<<"$CONFIG_JSON")

  if [[ "$all_fetched" == true ]]; then
    break
  fi

  if (( attempt == 1 || attempt % 12 == 0 )); then
    printf '  Ignition fetches not all visible yet (%d/%d)...\n' "$attempt" "$IGNITION_FETCH_ATTEMPTS"
  fi
  sleep "$IGNITION_FETCH_INTERVAL_SECONDS"
done

if [[ "${all_fetched:-false}" != true ]]; then
  echo "Not every SCOS node fetched its Ignition payload before the validation timeout." >&2
  echo "Inspect: make status-okd-nodes" >&2
  echo "         make okd-node-console NODE=$BOOTSTRAP_NAME" >&2
  exit 1
fi

printf '\nIgnition HTTP handoff observed for all managed runtime machines:\n'
if [[ "$BOOTSTRAP_ENABLED" == true ]]; then
  printf '  %-12s %s -> %s\n' "$BOOTSTRAP_NAME" "$BOOTSTRAP_IP" '/bootstrap.ign 200'
else
  printf '  %-12s %s\n' "$BOOTSTRAP_NAME" 'RETIRED (not recreated)'
fi
while IFS=$'\t' read -r name ip; do
  printf '  %-12s %s -> %s\n' "$name" "$ip" '/master.ign 200'
done < <(jq -r '.okd_control_planes[] | [.name, .ip] | @tsv' <<<"$CONFIG_JSON")

if [[ "$BOOTSTRAP_ENABLED" == true ]]; then
  printf '\nOKD runtime machines are BOOTSTRAPPING.\n'
  printf 'Next: make complete-okd-installation\n'
else
  printf '\nOKD runtime machines converged with bootstrap already retired.\n'
fi
