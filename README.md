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
- Terraform OpenStack owns the provider network, tenant network, router, security groups, reusable flavors, Ubuntu base image and workload VMs.
- The first persistent workload is `jenkins-controller` on `10.10.0.20`, with a dedicated Cinder data volume and a floating IP for controlled administration.
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

## Current next step

The OpenStack compute foundation is now defined in Terraform. Configure the HCP workspace `workload_ssh_public_key`, review the VCS-triggered plan, and create the first persistent `jenkins-controller` VM. See `docs/runbooks/openstack-compute.md`.
