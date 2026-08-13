# Terraform OpenStack runbook

## Execution model

The OpenStack Terraform configuration is intentionally executed through HCP
Terraform Agent mode:

```text
Git push
  -> HCP Terraform workspace
  -> private-banking-lab agent pool
  -> private-banking-ops-runner-01
  -> OpenStack APIs on 172.31.31.70
```

HCP Terraform owns the state and run history. The EC2 ops runner owns only the
runtime execution of `terraform init`, `plan` and `apply`; it does not keep the
repository or a local Terraform state as a source of truth.

Workspace working directory:

```text
infrastructure/terraform/openstack
```

The workspace should use VCS-triggered runs for changes under that directory and
manual apply confirmation.

## Terraform ownership

The first persistent OpenStack layer owns:

```text
public-net       192.168.250.0/24, flat physnet1, external
public-subnet    gateway 192.168.250.1, allocation 192.168.250.100-199
private-net      tenant network
private-subnet   10.10.0.0/24, DHCP enabled
lab-router       SNAT + private-subnet interface
lab-management   baseline management security group, including SSH from the AWS ops-runner subnet
lab.small        2 vCPU / 2048 MiB / 10 GiB
```

These values reproduce the topology that was already validated manually before
the Golden AMI was baked. The Golden baseline itself is workload-free, so these
resources are now created and owned only by Terraform.

## Compute foundation

The networking foundation is followed by the first persistent compute layer:

```text
Ubuntu 24.04 Glance image
lab.medium reusable flavor
workload SSH keypair
jenkins-controller port at 10.10.0.20
jenkins-controller VM
30 GiB Cinder data volume
floating IP allocated from public-net
```

The VM is intentionally the future Jenkins controller rather than a disposable
smoke-test instance. Jenkins software configuration remains outside Terraform
and will be owned by Ansible. See `docs/runbooks/openstack-compute.md`.

## Validation after apply

From the OpenStack host:

```bash
source /opt/openstack-client-venv/bin/activate
source /etc/kolla/admin-openrc.sh

openstack network list
openstack subnet list
openstack router list
openstack security group list
openstack flavor list
```

Expected named resources:

```text
public-net
public-subnet
private-net
private-subnet
lab-router
lab-management
lab.small
```

After the compute foundation validates end to end, the next phase is Ansible
configuration of the existing Jenkins VM and its persistent Cinder data volume.
