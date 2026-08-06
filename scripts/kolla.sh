#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-}
KOLLA_VENV=/opt/kolla-venv
KOLLA="$KOLLA_VENV/bin/kolla-ansible"
KOLLA_COLLECTIONS_PATH="$KOLLA_VENV/collections"
INVENTORY=/data/openstack/kolla/inventory/all-in-one
CONFIG_DIR=/etc/kolla
SECRETS_DIR=/data/openstack/secrets
CLIENT_VENV=/opt/openstack-client-venv

# Kolla shells out to ansible-playbook/ansible-galaxy by command name.
# Keep its own virtualenv first in PATH so the pinned Ansible runtime is used.
export PATH="$KOLLA_VENV/bin:$PATH"
export ANSIBLE_COLLECTIONS_PATH="$KOLLA_COLLECTIONS_PATH:$HOME/.ansible/collections:/usr/share/ansible/collections"

require_file() {
  if [ ! -e "$1" ]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_file "$KOLLA"
require_file "$INVENTORY"
require_file "$CONFIG_DIR/globals.yml"
require_file "$CONFIG_DIR/passwords.yml"

case "$ACTION" in
  prepare)
    "$KOLLA" bootstrap-servers -i "$INVENTORY"
    sudo systemctl restart private-banking-openstack-external-network.service
    "$KOLLA" prechecks -i "$INVENTORY" --use-test-images
    ;;
  prechecks)
    "$KOLLA" prechecks -i "$INVENTORY" --use-test-images
    ;;
  deploy)
    "$KOLLA" prechecks -i "$INVENTORY" --use-test-images
    "$KOLLA" pull -i "$INVENTORY"
    "$KOLLA" deploy -i "$INVENTORY"
    "$KOLLA" post-deploy
    sudo systemctl restart private-banking-openstack-external-network.service

    install -d -m 0700 "$SECRETS_DIR"
    if [ -f "$CONFIG_DIR/clouds.yaml" ] && [ ! -L "$CONFIG_DIR/clouds.yaml" ]; then
      install -m 0600 "$CONFIG_DIR/clouds.yaml" "$SECRETS_DIR/clouds.yaml"
      rm -f "$CONFIG_DIR/clouds.yaml"
      ln -s "$SECRETS_DIR/clouds.yaml" "$CONFIG_DIR/clouds.yaml"
    fi
    ;;
  reconfigure)
    "$KOLLA" prechecks -i "$INVENTORY" --use-test-images
    "$KOLLA" reconfigure -i "$INVENTORY"
    ;;
  stop)
    "$KOLLA" stop -i "$INVENTORY"
    ;;
  status)
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    ;;
  validate)
    "$KOLLA" validate-config -i "$INVENTORY"
    require_file "$SECRETS_DIR/clouds.yaml"
    export OS_CLIENT_CONFIG_FILE="$SECRETS_DIR/clouds.yaml"
    "$CLIENT_VENV/bin/openstack" --os-cloud kolla-admin service list
    "$CLIENT_VENV/bin/openstack" --os-cloud kolla-admin compute service list
    "$CLIENT_VENV/bin/openstack" --os-cloud kolla-admin hypervisor list
    "$CLIENT_VENV/bin/openstack" --os-cloud kolla-admin network agent list
    "$CLIENT_VENV/bin/openstack" --os-cloud kolla-admin volume service list
    ;;
  *)
    echo "Usage: $0 {prepare|prechecks|deploy|reconfigure|stop|status|validate}" >&2
    exit 2
    ;;
esac
