# OpenStack Golden AMI workflow

The Golden AMI is a reusable image of the validated Kolla all-in-one OpenStack host.
The AMI contains snapshots for all three attached EBS volumes: root, `/data`, and the
Cinder LVM device. Terraform remains responsible for the AWS host and later the
Terraform OpenStack layer remains responsible for tenant networks, VMs and volumes.

## 1. Prepare the existing OpenStack host

On the current EC2, after pulling the latest repository:

```bash
make validate-openstack
make prepare-golden-ami
```

`prepare-golden-ami` removes only the known end-to-end test resources (`lab-vm01`,
`test-cinder-volume`, `lab-router`, `private-net`, `public-net`, `lab-key`,
`lab-ssh`, `ubuntu-24.04`, and `lab.small`), verifies the empty control plane, flushes
filesystems and cleans cloud-init state for cloning.

Do not make configuration changes after this step and before baking.

## 2. Bake from the Mac

From the repository root on the Mac:

```bash
make bake-golden-ami
```

The baker reads the source EC2 ID, region and fixed private IP from Terraform,
requires exactly three EBS devices, stops the source instance, creates the AMI from
that stopped instance, waits for the AMI and all three snapshots, and then restarts
the source instance if it was originally running.

## 3. Enable Golden mode locally

Use the AMI ID printed by the baker:

```bash
make activate-golden-ami AMI_ID=ami-xxxxxxxxxxxxxxxxx
cd infrastructure/terraform/aws
terraform plan
```

This writes `golden.auto.tfvars` (ignored by Git). Golden mode uses the baked AMI,
keeps the stable OpenStack host private IP, and disables the separately-created
bootstrap `/data` and Cinder EBS resources because those block devices are restored
from the AMI snapshots.

Review the plan carefully. Replacing the current source EC2 and destroying its old
bootstrap EBS volumes is expected only after the Golden AMI is confirmed available.

## 4. Apply and validate the cloned host

```bash
terraform apply
terraform output public_ip
```

On the new EC2:

```bash
sudo cloud-init status --wait
cat /etc/private-banking-lab/volumes.env
lsblk
sudo vgs
make openstack-status
make validate-openstack
```

The host must have the configured stable private IP and three EBS devices. Horizon
should return HTTP 302 on port 80. The Golden first-boot user-data rediscovers the
new EBS serials by the `/data` filesystem and `cinder-volumes` VG, then reasserts the
host-side external network and Docker startup.

To return Terraform to the original stock-Ubuntu bootstrap path:

```bash
make deactivate-golden-ami
```
