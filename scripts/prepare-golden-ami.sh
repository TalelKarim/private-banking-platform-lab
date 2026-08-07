#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OPENSTACK=/opt/openstack-client-venv/bin/openstack
CLOUDS_FILE=/data/openstack/secrets/clouds.yaml
CLOUD=kolla-admin
READY_MARKER=/data/openstack/.golden-ami-ready

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this command as the ubuntu user, not as root." >&2
  exit 1
fi

sudo -n true

if [ ! -x "$OPENSTACK" ]; then
  echo "OpenStack client not found at $OPENSTACK" >&2
  exit 1
fi

if [ ! -r "$CLOUDS_FILE" ]; then
  echo "OpenStack cloud config not found at $CLOUDS_FILE" >&2
  exit 1
fi

export OS_CLIENT_CONFIG_FILE="$CLOUDS_FILE"

os() {
  "$OPENSTACK" --os-cloud "$CLOUD" "$@"
}

# Neutron list commands do not expose a generic --all-projects switch.
# Resolve the project carried by the kolla-admin token once and use the
# supported --project filter for project-owned Neutron resources.
PROJECT_ID=$(os token issue -f value -c project_id)
if [ -z "$PROJECT_ID" ]; then
  echo "Unable to resolve the OpenStack project ID from the kolla-admin token." >&2
  exit 1
fi

exists() {
  os "$@" >/dev/null 2>&1
}

wait_until_gone() {
  local kind=$1
  local name=$2
  local attempts=${3:-60}

  for _ in $(seq 1 "$attempts"); do
    if ! os "$kind" show "$name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for $kind '$name' to disappear." >&2
  return 1
}

wait_volume_available() {
  local name=$1
  local attempts=${2:-60}
  local status=""

  for _ in $(seq 1 "$attempts"); do
    if ! exists volume show "$name"; then
      return 0
    fi

    status=$(os volume show -f value -c status "$name" 2>/dev/null || true)
    if [ "$status" = "available" ]; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for volume '$name' to become available." >&2
  return 1
}

assert_empty() {
  local description=$1
  shift
  local output
  output=$(os "$@")
  if [ -n "${output//[[:space:]]/}" ]; then
    echo "Golden AMI preparation refused: $description still exist:" >&2
    echo "$output" >&2
    exit 1
  fi
}

echo "=== Validating OpenStack before Golden AMI cleanup ==="
"$ROOT_DIR/scripts/kolla.sh" validate

if ! mountpoint -q /data; then
  echo "/data is not mounted." >&2
  exit 1
fi

if ! sudo vgs cinder-volumes >/dev/null 2>&1; then
  echo "Cinder volume group 'cinder-volumes' is missing." >&2
  exit 1
fi

if [ ! -e /dev/kvm ]; then
  echo "/dev/kvm is missing." >&2
  exit 1
fi

if sudo docker ps --format '{{.Names}} {{.Status}}' | grep -qi 'unhealthy'; then
  echo "At least one running Kolla container is unhealthy." >&2
  sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  exit 1
fi

echo "=== Removing the known end-to-end validation resources ==="

# Release the floating IP first so no external mapping remains in the image.
if exists floating ip show 192.168.250.199; then
  os floating ip delete 192.168.250.199
fi

# Delete the test server. Cinder detaches its volume as part of server teardown.
if exists server show lab-vm01; then
  os server delete --wait lab-vm01
fi

# Delete the test Cinder volume after Nova has detached it.
if exists volume show test-cinder-volume; then
  wait_volume_available test-cinder-volume
  os volume delete test-cinder-volume
  wait_until_gone volume test-cinder-volume
fi

# Disconnect and remove the test router before deleting its networks.
if exists router show lab-router; then
  if exists subnet show private-subnet; then
    os router remove subnet lab-router private-subnet >/dev/null 2>&1 || true
  fi
  os router unset --external-gateway lab-router >/dev/null 2>&1 || true
  os router delete lab-router
  wait_until_gone router lab-router
fi

for subnet in private-subnet public-subnet; do
  if exists subnet show "$subnet"; then
    os subnet delete "$subnet"
  fi
done

for network in private-net public-net; do
  if exists network show "$network"; then
    os network delete "$network"
  fi
done

if exists security group show lab-ssh; then
  os security group delete lab-ssh
fi

if exists keypair show lab-key; then
  os keypair delete lab-key
fi

if exists image show ubuntu-24.04; then
  os image delete ubuntu-24.04
fi

if exists flavor show lab.small; then
  os flavor delete lab.small
fi

# Do not bake the private SSH key or host-specific known_hosts entries used by
# the validation VM into the reusable image.
rm -f "$HOME/.ssh/openstack_lab" "$HOME/.ssh/openstack_lab.pub"
ssh-keygen -R 192.168.250.199 >/dev/null 2>&1 || true

echo "=== Verifying that the Golden AMI baseline is workload-free ==="
assert_empty "Nova servers" server list --all-projects -f value -c ID
assert_empty "Cinder volumes" volume list --all-projects -f value -c ID
assert_empty "floating IPs in the admin project" floating ip list --project "$PROJECT_ID" -f value -c ID
assert_empty "routers in the admin project" router list --project "$PROJECT_ID" -f value -c ID
assert_empty "tenant networks in the admin project" network list --project "$PROJECT_ID" -f value -c ID
assert_empty "Glance images" image list -f value -c ID
assert_empty "flavors" flavor list -f value -c ID
assert_empty "keypairs" keypair list -f value -c Name

# The default security group is expected to remain. The test group must not.
if exists security group show lab-ssh; then
  echo "Test security group lab-ssh still exists." >&2
  exit 1
fi

echo "=== Re-validating the empty OpenStack control plane ==="
"$ROOT_DIR/scripts/kolla.sh" validate

# Flush filesystem buffers before the Mac-side baker stops the EC2 instance.
sudo sync
sudo fstrim -av || true

# Golden-image hygiene. On the next instance boot cloud-init must behave as a
# first boot and generate a new machine identity / SSH host keys.
sudo cloud-init clean --logs --machine-id

sudo install -d -m 0755 /data/openstack
printf 'prepared_at_utc=%s\nprivate_ip=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(hostname -I | awk '{print $1}')" \
  | sudo tee "$READY_MARKER" >/dev/null
sudo chmod 0644 "$READY_MARKER"

echo
echo "Golden AMI source is READY."
echo "Do not run more configuration changes before baking."
echo "Next, from your Mac, run: make bake-golden-ami"
