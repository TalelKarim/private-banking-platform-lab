# OpenShift host capacity baseline

This runbook fixes the durable AWS capacity used by the nested OpenStack host before
provisioning the OKD/OpenShift cluster. It does not create OpenShift resources yet.

## Declared capacity

- `lab-host`: `r8i.4xlarge` (16 vCPU, 128 GiB class).
- root EBS: 30 GiB gp3, unchanged.
- `/data` EBS: 600 GiB gp3. This filesystem backs Docker/Kolla, Glance and Nova
  instance root disks.
- Cinder backend EBS: 100 GiB gp3, unchanged. Persistent application PVC storage
  remains physically separated from Nova/root-disk capacity.

The 600 GiB `/data` target leaves useful headroom while a temporary 100 GiB OKD
bootstrap VM coexists with three 100 GiB compact control-plane/worker nodes and the
existing Jenkins/PostgreSQL VMs. After bootstrap removal, the same capacity remains
available for images, logs, Nova overhead and future lab growth.

## Golden AMI behavior

The Golden AMI contains snapshots of root, `/data` and Cinder. Terraform now reads
the two non-root snapshot mappings and overrides their runtime EBS sizes when a new
Golden instance is launched. `/data` is therefore restored from the baked snapshot
but can be launched at 600 GiB even if the snapshot was created from a 200 GiB
volume. The Golden first-boot script runs `resize2fs` so the preserved ext4
filesystem consumes the enlarged EBS block device.

Cinder remains at 100 GiB. Its snapshot/LVM metadata is restored unchanged.

## Validation after apply/rebuild

On `lab-host`:

```bash
nproc
free -h
lsblk
df -h /data
sudo lvs
```

Expected high-level result:

```text
CPU        : 16 vCPU visible to lab-host
RAM        : ~128 GiB class
/data EBS  : ~600 GiB raw, ext4 expanded online
Cinder EBS : 100 GiB, cinder-volumes VG still healthy
```

Then validate OpenStack itself:

```bash
source /opt/openstack-client-venv/bin/activate
source /etc/kolla/admin-openrc.sh
openstack hypervisor stats show
openstack server list
openstack volume list
```

Existing workload counts should remain explainable by their flavors. The next step
is to define the dedicated OpenShift network and the OKD node flavor; this capacity
change alone does not create any OKD VM.
