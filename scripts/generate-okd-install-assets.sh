#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLUSTER_CONFIG="$ROOT_DIR/platform/openshift/cluster-config.yml"
RUNTIME_ROOT=${OKD_RUNTIME_ROOT:-$ROOT_DIR/.runtime/openshift}
INSTALL_DIR="$RUNTIME_ROOT/install"
READY_FILE="$RUNTIME_ROOT/install-assets.ready"
TF_STATE="$RUNTIME_ROOT/terraform-nodes/terraform.tfstate"
WORKLOAD_SSH_PRIVATE_KEY=${WORKLOAD_SSH_PRIVATE_KEY:-/home/ubuntu/.ssh/private-banking-openstack-workloads}
ANSIBLE_PYTHON=${ANSIBLE_PYTHON:-/opt/ansible-venv/bin/python}
MAX_ASSET_AGE_SECONDS=${OKD_INSTALL_ASSET_MAX_AGE_SECONDS:-36000}

# OKD allows a fake pull secret when no authenticated/private registry access is
# required. A real pull secret can still be supplied at runtime through
# OKD_PULL_SECRET without ever committing it to Git.
DEFAULT_PULL_SECRET='{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}'
OKD_PULL_SECRET=${OKD_PULL_SECRET:-$DEFAULT_PULL_SECRET}

for binary in openshift-install ssh-keygen sha256sum stat date; do
  command -v "$binary" >/dev/null 2>&1 || {
    echo "Required command not found: $binary" >&2
    exit 1
  }
done

if [[ ! -x "$ANSIBLE_PYTHON" ]]; then
  echo "Python from the Ansible control environment is required: $ANSIBLE_PYTHON" >&2
  exit 1
fi

if [[ ! -r "$WORKLOAD_SSH_PRIVATE_KEY" ]]; then
  echo "Missing OpenStack workload SSH private key: $WORKLOAD_SSH_PRIVATE_KEY" >&2
  exit 1
fi

# Read the canonical YAML with PyYAML from the existing Ansible venv. Exporting
# shell-safe assignments keeps the orchestration script dependency-light.
eval "$("$ANSIBLE_PYTHON" - "$CLUSTER_CONFIG" <<'PY'
import shlex
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    cfg = yaml.safe_load(handle)

required = [
    "okd_cluster_name",
    "okd_base_domain",
    "okd_release_version",
    "okd_machine_network_cidr",
    "okd_pod_network_cidr",
    "okd_pod_host_prefix",
    "okd_service_network_cidr",
]
missing = [key for key in required if key not in cfg]
if missing:
    raise SystemExit("Missing OKD config keys: " + ", ".join(missing))

values = {
    "OKD_CLUSTER_NAME": str(cfg["okd_cluster_name"]),
    "OKD_BASE_DOMAIN": str(cfg["okd_base_domain"]),
    "OKD_VERSION": str(cfg["okd_release_version"]),
    "OKD_MACHINE_CIDR": str(cfg["okd_machine_network_cidr"]),
    "OKD_POD_CIDR": str(cfg["okd_pod_network_cidr"]),
    "OKD_POD_HOST_PREFIX": str(cfg["okd_pod_host_prefix"]),
    "OKD_SERVICE_CIDR": str(cfg["okd_service_network_cidr"]),
}
for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"

if ! openshift-install version | grep -Fq "$OKD_VERSION"; then
  echo "Pinned openshift-install $OKD_VERSION is not active. Run make prepare-okd-toolchain first." >&2
  exit 1
fi

SSH_PUBLIC_KEY=$(ssh-keygen -y -f "$WORKLOAD_SSH_PRIVATE_KEY")
if [[ -z "$SSH_PUBLIC_KEY" ]]; then
  echo "Failed to derive the public SSH key for the FCOS/SCOS core user." >&2
  exit 1
fi

mkdir -p "$RUNTIME_ROOT"
chmod 0700 "$RUNTIME_ROOT"

CONFIG_FINGERPRINT=$(
  {
    sha256sum "$CLUSTER_CONFIG"
    printf '%s\n' "$SSH_PUBLIC_KEY"
    printf '%s\n' "$OKD_PULL_SECRET"
    openshift-install version | sed -n '1,4p'
  } | sha256sum | awk '{print $1}'
)

# Installer assets are immutable first-boot material for an existing OKD
# control plane. If runtime Terraform already owns control-plane instances,
# regenerating master.ign/kubeconfig would describe a different installation
# and (before this guard existed) changed Terraform user_data, forcing all
# three compact masters to be replaced. Detect that state and make the
# operation fail-safe/idempotent.
runtime_has_control_planes=false
if [[ -s "$TF_STATE" ]]; then
  runtime_has_control_planes=$(
    "$ANSIBLE_PYTHON" - "$TF_STATE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        state = json.load(handle)
except (OSError, ValueError):
    print("false")
    raise SystemExit(0)

for resource in state.get("resources", []):
    if (resource.get("type") == "openstack_compute_instance_v2"
            and resource.get("name") == "control_plane"
            and resource.get("instances")):
        print("true")
        break
else:
    print("false")
PY
  )
fi

assets_are_reusable=false
if [[ -f "$READY_FILE" && -f "$INSTALL_DIR/bootstrap.ign" && -f "$INSTALL_DIR/master.ign" ]]; then
  previous_fingerprint=$(awk -F= '$1 == "fingerprint" {print $2}' "$READY_FILE" || true)
  created_epoch=$(awk -F= '$1 == "created_epoch" {print $2}' "$READY_FILE" || true)
  now_epoch=$(date +%s)

  if [[ "$runtime_has_control_planes" == true ]]; then
    if [[ "$previous_fingerprint" != "$CONFIG_FINGERPRINT" ]]; then
      echo "Refusing to regenerate OKD installer assets while control-plane VMs exist." >&2
      echo "The desired install-time configuration changed; perform an explicit OKD destroy/rebuild instead." >&2
      exit 1
    fi
    # Once nodes exist, asset age is irrelevant: Ignition has already been
    # consumed and the matching kubeconfig is the credential we must preserve.
    assets_are_reusable=true
    if [[ "$created_epoch" =~ ^[0-9]+$ ]]; then
      age=$((now_epoch - created_epoch))
    fi
  elif [[ "$previous_fingerprint" == "$CONFIG_FINGERPRINT" && "$created_epoch" =~ ^[0-9]+$ ]]; then
    age=$((now_epoch - created_epoch))
    if (( age >= 0 && age < MAX_ASSET_AGE_SECONDS )); then
      assets_are_reusable=true
    fi
  fi
fi

if [[ "$runtime_has_control_planes" == true && "$assets_are_reusable" != true ]]; then
  echo "Existing OKD control-plane VMs were found, but their original installer assets are missing or inconsistent." >&2
  echo "Refusing to generate a new cluster identity over live nodes. Preserve/recover .runtime/openshift or explicitly rebuild OKD." >&2
  exit 1
fi

if [[ "$assets_are_reusable" == true ]]; then
  if [[ "$runtime_has_control_planes" == true ]]; then
    echo "Existing OKD control-plane VMs detected; preserving their original installer assets."
  else
    echo "Fresh OKD installation assets already exist; reusing them."
  fi
  echo "  directory: $INSTALL_DIR"
  [[ -n "${age:-}" ]] && echo "  age:       $age seconds"
  exit 0
fi

rm -rf "$INSTALL_DIR"
install -d -m 0700 "$INSTALL_DIR"

export OKD_CLUSTER_NAME OKD_BASE_DOMAIN OKD_MACHINE_CIDR OKD_POD_CIDR
export OKD_POD_HOST_PREFIX OKD_SERVICE_CIDR OKD_PULL_SECRET SSH_PUBLIC_KEY INSTALL_DIR

# Build the install-config declaratively instead of using the interactive
# installer wizard. Terraform owns the OpenStack infrastructure, therefore the
# installer uses the documented UPI platform type "none" and creates no VMs.
"$ANSIBLE_PYTHON" <<'PY'
import os
from pathlib import Path
import yaml

install_dir = Path(os.environ["INSTALL_DIR"])
config = {
    "apiVersion": "v1",
    "baseDomain": os.environ["OKD_BASE_DOMAIN"],
    "metadata": {"name": os.environ["OKD_CLUSTER_NAME"]},
    "compute": [
        {
            "name": "worker",
            "replicas": 0,
            "platform": {},
        }
    ],
    "controlPlane": {
        "name": "master",
        "replicas": 3,
        "platform": {},
    },
    "networking": {
        "networkType": "OVNKubernetes",
        "machineNetwork": [{"cidr": os.environ["OKD_MACHINE_CIDR"]}],
        "clusterNetwork": [
            {
                "cidr": os.environ["OKD_POD_CIDR"],
                "hostPrefix": int(os.environ["OKD_POD_HOST_PREFIX"]),
            }
        ],
        "serviceNetwork": [os.environ["OKD_SERVICE_CIDR"]],
    },
    "platform": {"none": {}},
    "pullSecret": os.environ["OKD_PULL_SECRET"],
    "sshKey": os.environ["SSH_PUBLIC_KEY"],
}

text = yaml.safe_dump(config, sort_keys=False)
(install_dir / "install-config.yaml").write_text(text, encoding="utf-8")
(install_dir / "install-config.backup.yaml").write_text(text, encoding="utf-8")
PY
chmod 0600 "$INSTALL_DIR/install-config.yaml" "$INSTALL_DIR/install-config.backup.yaml"

printf 'Generating OKD manifests for %s.%s...\n' "$OKD_CLUSTER_NAME" "$OKD_BASE_DOMAIN"
openshift-install create manifests --dir "$INSTALL_DIR"

SCHEDULER_MANIFEST="$INSTALL_DIR/manifests/cluster-scheduler-02-config.yml"
if [[ ! -f "$SCHEDULER_MANIFEST" ]]; then
  echo "Expected scheduler manifest was not generated: $SCHEDULER_MANIFEST" >&2
  exit 1
fi

# A three-node compact cluster has no dedicated workers. Explicitly allow the
# three control-plane nodes to schedule normal application workloads.
"$ANSIBLE_PYTHON" - "$SCHEDULER_MANIFEST" <<'PY'
import sys
import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    doc = yaml.safe_load(handle)

doc.setdefault("spec", {})["mastersSchedulable"] = True
with open(path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(doc, handle, sort_keys=False)
PY

if ! grep -Eq '^[[:space:]]*mastersSchedulable:[[:space:]]*true[[:space:]]*$' "$SCHEDULER_MANIFEST"; then
  echo "Compact-cluster scheduler manifest is not mastersSchedulable=true" >&2
  exit 1
fi

printf 'Generating bootstrap/master Ignition and cluster credentials...\n'
openshift-install create ignition-configs --dir "$INSTALL_DIR"

for required in \
  "$INSTALL_DIR/bootstrap.ign" \
  "$INSTALL_DIR/master.ign" \
  "$INSTALL_DIR/worker.ign" \
  "$INSTALL_DIR/metadata.json" \
  "$INSTALL_DIR/auth/kubeconfig" \
  "$INSTALL_DIR/auth/kubeadmin-password"; do
  [[ -s "$required" ]] || {
    echo "Expected installer asset missing or empty: $required" >&2
    exit 1
  }
done

chmod -R go-rwx "$INSTALL_DIR"
(
  cd "$INSTALL_DIR"
  sha256sum bootstrap.ign master.ign > ignition.sha256
)

created_epoch=$(date +%s)
cat > "$READY_FILE" <<EOF_READY
fingerprint=$CONFIG_FINGERPRINT
created_epoch=$created_epoch
okd_version=$OKD_VERSION
cluster=$OKD_CLUSTER_NAME.$OKD_BASE_DOMAIN
EOF_READY
chmod 0600 "$READY_FILE"

printf '\nFresh OKD installation assets are ready:\n'
printf '  install dir : %s\n' "$INSTALL_DIR"
printf '  cluster     : %s.%s\n' "$OKD_CLUSTER_NAME" "$OKD_BASE_DOMAIN"
printf '  bootstrap   : %s\n' "$INSTALL_DIR/bootstrap.ign"
printf '  master      : %s\n' "$INSTALL_DIR/master.ign"
printf '  kubeconfig  : %s\n' "$INSTALL_DIR/auth/kubeconfig"
printf '  note        : assets are runtime-only and expire; they are never committed to Git\n'
