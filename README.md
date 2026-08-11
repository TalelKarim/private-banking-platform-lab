# Private Banking Platform Lab

A reproducible private-banking platform lab built in layers:

```text
AWS EC2 + nested KVM
  -> Kolla-Ansible OpenStack
    -> Terraform OpenStack networks/VMs/volumes
      -> Ansible Jenkins/PostgreSQL/tooling
        -> OpenShift and application workloads
```

## Current implemented phase

The repository now contains the automation needed to deploy an OpenStack 2026.1
all-in-one control plane on AWS and the first Terraform-managed OpenStack
foundation above it.

- Terraform AWS creates the OpenStack EC2 host, its storage, and a separate ops-runner EC2.
- Minimal cloud-init makes the machine automation-ready and mounts `/data`.
- Project Ansible prepares KVM, host networking, Cinder LVM and Kolla-Ansible.
- The ops runner hosts the HCP Terraform Agent that executes OpenStack plans/applies and will later run Ansible workloads.
- Kolla-Ansible bootstraps Docker, runs prechecks and deploys OpenStack.
- HCP Terraform stores the OpenStack state/run history while Git changes trigger plans on the EC2 agent.
- Terraform OpenStack owns the provider network, tenant network, router, baseline management security group and baseline flavor.
- Generated passwords and admin credentials stay outside Git under `/data`.

## Main commands

From the EC2 after cloning the repository:

```bash
make prepare-openstack
make deploy-openstack
make validate-openstack
```

Or run the complete chain:

```bash
make openstack-up
```

See `docs/runbooks/openstack-deployment.md` for the exact rebuild and deployment
procedure.

## Repository structure

```text
private-banking-platform-lab/
├── infrastructure/
│   ├── terraform/
│   │   ├── aws/
│   │   └── openstack/
│   ├── ansible/
│   │   ├── inventories/
│   │   ├── playbooks/
│   │   └── roles/
│   └── openstack/
│       └── kolla/
├── applications/
│   ├── portfolio-java/
│   └── risk-engine-dotnet/
├── scripts/
├── docs/
└── Makefile
```
