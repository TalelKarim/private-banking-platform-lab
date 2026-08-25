#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ANSIBLE_DIR="$ROOT_DIR/infrastructure/ansible"
ANSIBLE_PLAYBOOK=${ANSIBLE_PLAYBOOK:-/opt/ansible-venv/bin/ansible-playbook}
ANSIBLE_BIN=${ANSIBLE_BIN:-/opt/ansible-venv/bin/ansible}
ANSIBLE_GALAXY=${ANSIBLE_GALAXY:-/opt/ansible-venv/bin/ansible-galaxy}
INVENTORY="$ANSIBLE_DIR/inventories/workloads/hosts.yml"
COLLECTIONS_DIR="$ANSIBLE_DIR/.collections"
POSTGRESQL_COLLECTION_MANIFEST="$COLLECTIONS_DIR/ansible_collections/community/postgresql/MANIFEST.json"
WORKLOAD_KEY=/home/ubuntu/.ssh/private-banking-openstack-workloads
POSTGRESQL_FLOATING_IP=${1:-${POSTGRESQL_FLOATING_IP:-}}

if [[ -z "$POSTGRESQL_FLOATING_IP" ]]; then
  echo "Usage: $0 <postgresql-floating-ip>" >&2
  echo "Example: $0 192.168.250.104" >&2
  exit 2
fi

python3 - "$POSTGRESQL_FLOATING_IP" <<'PY'
import ipaddress
import sys
ipaddress.IPv4Address(sys.argv[1])
PY

for executable in "$ANSIBLE_PLAYBOOK" "$ANSIBLE_BIN" "$ANSIBLE_GALAXY"; do
  if [[ ! -x "$executable" ]]; then
    echo "Missing Ansible executable: $executable" >&2
    echo "Rebuild/bootstrap the ops-runner first." >&2
    exit 1
  fi
done

if [[ ! -r "$WORKLOAD_KEY" ]]; then
  echo "Missing workload SSH key: $WORKLOAD_KEY" >&2
  exit 1
fi

if [[ "$(stat -c '%a' "$WORKLOAD_KEY")" != "600" ]]; then
  echo "The workload SSH private key must have mode 0600: $WORKLOAD_KEY" >&2
  exit 1
fi

mkdir -p "$COLLECTIONS_DIR"
if [[ ! -f "$POSTGRESQL_COLLECTION_MANIFEST" ]]; then
  printf '==> Installing pinned Ansible collections required by PostgreSQL\n'
  "$ANSIBLE_GALAXY" collection install \
    -r "$ANSIBLE_DIR/collections/requirements.yml" \
    -p "$COLLECTIONS_DIR"
fi

export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
EXTRA_VARS="postgresql_ansible_host=$POSTGRESQL_FLOATING_IP"

cd "$ANSIBLE_DIR"

printf '==> SSH/Ansible connectivity check to PostgreSQL (%s)\n' "$POSTGRESQL_FLOATING_IP"
"$ANSIBLE_BIN" \
  -i "$INVENTORY" \
  postgresql_servers \
  -m ansible.builtin.ping \
  -e "$EXTRA_VARS"

printf '==> Configuring PostgreSQL on the Cinder-backed data volume\n'
"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  playbooks/configure-postgresql.yml \
  -e "$EXTRA_VARS"
