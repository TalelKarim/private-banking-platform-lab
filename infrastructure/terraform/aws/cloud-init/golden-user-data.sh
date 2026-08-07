#!/usr/bin/env bash
set -euxo pipefail

exec > >(
  tee -a /var/log/private-banking-lab-golden-boot.log |
  logger -t private-banking-lab-golden-boot -s 2>/dev/console
) 2>&1

echo "=== Starting Golden AMI first-boot reconciliation ==="

# /etc/fstab was baked with the filesystem UUID of the /data snapshot. The
# cloned EBS volume keeps that filesystem UUID, so mount it before discovery.
mkdir -p /data
for attempt in $(seq 1 120); do
  mount -a || true
  mountpoint -q /data && break
  sleep 2
done
mountpoint -q /data

DATA_DEVICE=$(readlink -f "$(findmnt -n -o SOURCE /data)")
DATA_SERIAL=$(lsblk -dn -o SERIAL "$DATA_DEVICE" | awk '{$1=$1};1')

# The Cinder snapshot preserves the LVM PV/VG metadata. Activate it and locate
# the PV by the stable VG name rather than by an EC2 device name.
vgchange -ay cinder-volumes || true
CINDER_DEVICE=""
for attempt in $(seq 1 120); do
  CINDER_DEVICE=$(pvs --noheadings -o pv_name --select vg_name=cinder-volumes 2>/dev/null | awk 'NF {print $1; exit}')
  [[ -n "$CINDER_DEVICE" ]] && break
  sleep 2
done

if [[ -z "$CINDER_DEVICE" ]]; then
  echo "ERROR: Cinder PV for VG cinder-volumes was not found" >&2
  exit 1
fi

CINDER_DEVICE=$(readlink -f "$CINDER_DEVICE")
CINDER_SERIAL=$(lsblk -dn -o SERIAL "$CINDER_DEVICE" | awk '{$1=$1};1')

if [[ -z "$DATA_SERIAL" || -z "$CINDER_SERIAL" ]]; then
  echo "ERROR: failed to resolve cloned EBS volume serials" >&2
  exit 1
fi

install -d -m 0755 /etc/private-banking-lab
cat > /etc/private-banking-lab/volumes.env <<EOF_VOLUMES
DATA_VOLUME_SERIAL=${DATA_SERIAL}
CINDER_VOLUME_SERIAL=${CINDER_SERIAL}
EOF_VOLUMES
chmod 0644 /etc/private-banking-lab/volumes.env
rm -f /data/openstack/.golden-ami-ready

# Reassert the host-side OpenStack external network before/with Docker startup.
systemctl enable --now private-banking-openstack-external-network.service
systemctl enable --now docker

echo "Golden AMI volume metadata refreshed:"
echo "  data   -> $DATA_DEVICE ($DATA_SERIAL)"
echo "  cinder -> $CINDER_DEVICE ($CINDER_SERIAL)"
echo "=== Golden AMI first-boot reconciliation completed ==="
