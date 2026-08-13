# OpenStack compute foundation runbook

## Goal

This phase turns the OpenStack control plane into a consumable platform by
creating the reusable Ubuntu base image and the first persistent workload VM.
The first VM is the future Jenkins controller; it is not a disposable smoke
test.

```text
Canonical Ubuntu 24.04 image
  -> Glance base image
    -> reusable Nova flavor + keypair
      -> explicit Neutron port on private-net
        -> Jenkins controller VM 10.10.0.20
          -> Cinder data volume
          -> floating IP on public-net
```

Terraform owns the infrastructure only. Jenkins itself will be installed and
configured in the next layer by Ansible, so application configuration can be
changed without recreating the VM.

## One-time HCP Terraform input

The OpenStack provider must inject an SSH public key into the VM, but Terraform
must not generate the private key inside the HCP OpenStack state. The existing
AWS lab key is reused instead.

From the repository on the Mac, derive the public key from the existing lab
private key without exposing the private key itself:

```bash
ssh-keygen -y \
  -f infrastructure/terraform/aws/.keys/private-banking-platform-lab.pem
```

In the HCP Terraform workspace `private-banking-platform-lab-openstack`, create
a Terraform variable named:

```text
workload_ssh_public_key
```

Paste the command output as its value. The value is a public key, not a secret;
marking it sensitive in HCP is optional.

## Expected plan

The OpenStack run should add, without replacing the existing network foundation:

```text
ubuntu-24.04-noble-amd64-20260801  Glance image
lab.medium                         Nova flavor (2 vCPU / 4 GiB / 20 GiB root)
private-banking-lab-workloads      Nova keypair
jenkins-controller                 application security group
jenkins-controller-port            Neutron port, fixed IP 10.10.0.20
jenkins-controller                 Nova VM
jenkins-controller-data            30 GiB Cinder volume
one floating IP                    allocated from public-net
```

Do not confirm the HCP apply if the plan proposes deleting or replacing
`public-net`, `private-net`, `lab-router`, `lab-management` or `lab.small`.

Before apply, confirm that the stable Jenkins address is not already occupied:

```bash
openstack port list --fixed-ip ip-address=10.10.0.20
```

The expected result is an empty list. If an old manual test VM still owns that
address, remove that disposable test resource first rather than changing the
Terraform address.

The image is pinned to Canonical's Ubuntu 24.04 released build dated 2026-08-01.
The OpenStack provider downloads the image on the HCP agent and uploads it to
Glance, so the first apply can take noticeably longer than the networking-only
foundation run.

## Validation after apply

On the OpenStack lab host:

```bash
source /opt/openstack-client-venv/bin/activate
source /etc/kolla/admin-openrc.sh

openstack image show ubuntu-24.04-noble-amd64-20260801
openstack flavor show lab.medium
openstack keypair show private-banking-lab-workloads
openstack server show jenkins-controller
openstack port show jenkins-controller-port
openstack volume show jenkins-controller-data
openstack floating ip list
```

The VM must be `ACTIVE`, its fixed address must be `10.10.0.20`, the Cinder
volume must be attached, and the floating IP must be associated with the Jenkins
port.

Check outbound connectivity from the VM through the lab host with SSH ProxyJump.
The same RSA key is accepted by both the AWS lab host and the OpenStack VM:

```bash
LAB_HOST_PUBLIC_IP=$(terraform -chdir=infrastructure/terraform/aws output -raw public_ip)
JENKINS_FIP=<floating-ip-shown-by-HCP-output>
KEY=infrastructure/terraform/aws/.keys/private-banking-platform-lab.pem

ssh -i "$KEY" \
  -o "ProxyJump=ubuntu@${LAB_HOST_PUBLIC_IP}" \
  ubuntu@"${JENKINS_FIP}"
```

Inside the VM:

```bash
ip address
ip route
ping -c 3 1.1.1.1
getent hosts archive.ubuntu.com
lsblk
```

Do not format or mount the attached Cinder volume manually. The next Ansible
phase will own filesystem creation and the permanent Jenkins data mount.
