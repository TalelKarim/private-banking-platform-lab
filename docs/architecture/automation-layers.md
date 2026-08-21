# Automation layers

```text
Terraform AWS
  -> lab-host: nested OpenStack host, storage, IAM, Security Groups and routing
  -> ops-runner: HCP Terraform Agent + administration tooling
  -> edge-gateway: Elastic IP + HTTP/HTTPS/SSH perimeter

Minimal cloud-init
  -> lab-host: boot readiness and persistent /data mount
  -> ops-runner: Terraform/Ansible/OpenStack CLI, EC2 Instance Connect, HCP agent,
     SSM-backed SSH material and project repository checkout
  -> edge-gateway: hostname, SSH/SSM/Python bootstrap only

Project Ansible - OpenStack host layer
  -> KVM prerequisites, kernel/network settings, os-host <-> os-ext veth,
     outbound NAT, routed forwarding, Cinder LVM and Kolla configuration

Kolla-Ansible
  -> Docker bootstrap, prechecks, OpenStack container deployment and post-deploy

Terraform OpenStack (HCP Terraform Agent on ops-runner)
  -> provider/private networks, router, security groups, images and flavors
  -> workload ports, VMs, Floating IPs and Cinder volumes
  -> dependency ordering so Floating IP workloads wait for the Neutron router path

Project Ansible - workload layer (executed on ops-runner)
  -> Jenkins controller + persistent volume
  -> edge-gateway Nginx routes
  -> future Jenkins agents, PostgreSQL, monitoring and OpenShift nodes

Configuration orchestrator
  -> make configure-lab
  -> discovers runtime addresses
  -> converges all current workload/edge Ansible playbooks in the required order
```

The separation is intentional: every layer owns one type of state and can be rerun without duplicating another layer's responsibility.

`ops-runner` is the administration/convergence plane. It does not host OpenStack services, Jenkins workloads or application data. `edge-gateway` is the HTTP/HTTPS ingress plane and does not run build jobs. `lab-host` is the nested infrastructure host and transit path, not an application ingress.

## Persistent data ownership rule

Cloud-init mounts `/data` but never recursively changes its ownership. Docker and OpenStack keep service-specific ownership under the persistent volume across EC2 replacement; only operator-owned directories are assigned to `ubuntu`.
