# Automation layers

```text
Terraform AWS
  -> EC2, EBS, IAM, Security Group, Spot, nested virtualization

Minimal cloud-init
  -> Python, Git, Make, SSM/SSH readiness, persistent /data mount

Project Ansible
  -> KVM host prerequisites, kernel/network settings, os-host <-> os-ext veth,
     outbound NAT, Cinder LVM, Terraform CLI, Kolla-Ansible installation/config

Kolla-Ansible
  -> Docker bootstrap, prechecks, OpenStack container deployment, post-deploy

Terraform OpenStack
  -> tenant networks, router, images, flavors, volumes and virtual machines

Ansible workload layer
  -> PostgreSQL, Jenkins, monitoring and later OpenShift node configuration
```

The separation is intentional: every layer owns one type of state and can be
rerun without duplicating the responsibility of another layer.

## Persistent data ownership rule

Cloud-init mounts `/data` but never recursively changes its ownership. Docker and
OpenStack keep service-specific ownership under the persistent volume across EC2
replacement; only operator-owned directories are assigned to `ubuntu`.
