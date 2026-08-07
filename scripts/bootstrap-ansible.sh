#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
VENV_DIR="$ROOT_DIR/.venv/ansible"
COLLECTIONS_DIR="$ANSIBLE_DIR/.collections"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this command as the ubuntu user, not as root." >&2
  exit 1
fi

sudo -n true
sudo cloud-init status --wait >/dev/null

BOOTSTRAP_READY=false
if grep -qF "=== Minimal private banking lab bootstrap completed ===" \
  /var/log/private-banking-lab-bootstrap.log 2>/dev/null; then
  BOOTSTRAP_READY=true
fi
if grep -qF "=== Golden AMI first-boot reconciliation completed ===" \
  /var/log/private-banking-lab-golden-boot.log 2>/dev/null; then
  BOOTSTRAP_READY=true
fi
if [ "$BOOTSTRAP_READY" != true ]; then
  echo "Neither the stock bootstrap nor the Golden AMI first-boot reconciliation reached its final marker." >&2
  exit 1
fi

if ! mountpoint -q /data; then
  echo "/data is not mounted. Check the persistent EBS attachment and cloud-init log." >&2
  exit 1
fi

if [ ! -r /etc/private-banking-lab/volumes.env ]; then
  echo "Missing /etc/private-banking-lab/volumes.env. Recreate the EC2 with the final cloud-init." >&2
  exit 1
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$ANSIBLE_DIR/requirements.txt"

mkdir -p "$COLLECTIONS_DIR"
"$VENV_DIR/bin/ansible-galaxy" collection install \
  -r "$ANSIBLE_DIR/collections/requirements.yml" \
  -p "$COLLECTIONS_DIR"

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
cd "$ANSIBLE_DIR"
"$VENV_DIR/bin/ansible-playbook" playbooks/prepare-openstack-host.yml
