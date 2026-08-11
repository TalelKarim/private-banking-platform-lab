# Automation layers

```text
Terraform AWS
  -> OpenStack EC2 host, EBS, IAM, Security Groups, Spot, nested virtualization
  -> dedicated ops-runner EC2 for Terraform/OpenStack and later Ansible execution

Minimal cloud-init
  -> OpenStack host: Python, Git, Make, SSM/SSH readiness, persistent /data mount
  -> ops runner: Terraform CLI, Ansible CLI, OpenStack CLI and administration workspace

Project Ansible
  -> KVM host prerequisites, kernel/network settings, os-host <-> os-ext veth,
     outbound NAT, Cinder LVM, Kolla-Ansible installation/config

Kolla-Ansible
  -> Docker bootstrap, prechecks, OpenStack container deployment, post-deploy

Terraform OpenStack (HCP Terraform Agent execution on the ops runner)
  -> tenant networks, router, images, flavors, volumes and virtual machines
  -> Git/VCS triggers runs in HCP Terraform
  -> HCP Terraform stores state/run history while the EC2 ops runner executes plan/apply

Ansible workload layer (later executed on the ops runner)
  -> PostgreSQL, Jenkins, monitoring and later OpenShift node configuration
```

The separation is intentional: every layer owns one type of state and can be
rerun without duplicating the responsibility of another layer. The ops runner is
an administration client of OpenStack; it does not host OpenStack services or
nested OpenStack virtual machines.

## Persistent data ownership rule

Cloud-init mounts `/data` but never recursively changes its ownership. Docker and
OpenStack keep service-specific ownership under the persistent volume across EC2
replacement; only operator-owned directories are assigned to `ubuntu`.
