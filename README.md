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

The repository now contains the complete automation needed to deploy an
OpenStack 2026.1 all-in-one control plane on the AWS lab host.

- Terraform AWS creates the EC2 host and two persistent EBS volumes.
- Minimal cloud-init makes the machine automation-ready and mounts `/data`.
- Project Ansible prepares KVM, host networking, Cinder LVM and Kolla-Ansible.
- Kolla-Ansible bootstraps Docker, runs prechecks and deploys OpenStack.
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
