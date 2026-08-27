# OpenShift / OKD OpenStack foundation

## Goal

This phase creates only the stable OpenStack infrastructure that must exist
before the first OKD control-plane boot. It deliberately does **not** create the
temporary bootstrap VM or the three compact OKD nodes yet, because those VMs
must receive their Ignition configuration on first boot.

```text
lab-router
  |
  +-- private-net      10.10.0.0/24
  |     +-- Jenkins controller
  |     +-- Jenkins worker
  |     +-- PostgreSQL
  |
  +-- openshift-net    10.20.0.0/24
        +-- 10.20.0.10 okd-lb       (created in this phase)
        +-- 10.20.0.11 bootstrap    (reserved, created later)
        +-- 10.20.0.21 okd-01       (reserved, created later)
        +-- 10.20.0.22 okd-02       (reserved, created later)
        +-- 10.20.0.23 okd-03       (reserved, created later)
```

## Terraform-owned resources

The OpenStack workspace now owns:

```text
openshift-net                     dedicated tenant network
openshift-subnet                  10.20.0.0/24, gateway 10.20.0.1
lab-router interface              routes the new subnet through Neutron
DHCP allocation pool              10.20.0.100-10.20.0.199
okd.control                       4 vCPU / 16384 MiB / 100 GiB root
openshift-nodes security group    future bootstrap/control-plane east-west traffic
okd-lb security group             DNS/API/MCS/Ingress/Ignition entry point
okd-lb                            Ubuntu VM, fixed IP 10.20.0.10 + management FIP
```

`okd-lb` intentionally reuses `lab.small` (2 vCPU / 2 GiB / 10 GiB). It only
hosts lightweight infrastructure services: HAProxy, DNS and a temporary HTTP
endpoint for Ignition artifacts.

`openshift-subnet` advertises `10.20.0.10` (`okd-lb`) as its DNS server from
the beginning. That makes the future bootstrap/control-plane nodes consume the
private cluster DNS automatically on first boot. To avoid the bootstrap
chicken-and-egg problem, `okd-lb` receives a tiny cloud-init override that makes
**its own** system resolver use public upstreams until Ansible installs the DNS
service on `10.20.0.10`. No OKD node is created before that Ansible convergence
has succeeded.

## Why no OKD nodes yet

The required ordering is:

```text
Terraform foundation
  -> okd-lb exists
  -> Ansible configures DNS + HAProxy + Ignition HTTP
  -> openshift-install generates bootstrap.ign/master.ign
  -> Terraform creates bootstrap + three OKD nodes with first-boot Ignition
```

Creating the nodes in this foundation apply would be too early: their first boot
would happen before the installer-generated Ignition artifacts exist.

## Expected HCP Terraform plan

The VCS-triggered OpenStack run should add the new OpenShift foundation without
replacing existing Jenkins/PostgreSQL resources or the existing networks.

High-level additions:

```text
1 network
1 subnet
1 router interface
1 OKD flavor
2 security groups + their rules
1 okd-lb port
1 okd-lb VM
1 floating IP for okd-lb management
```

Do not confirm the apply if the plan proposes replacing or deleting:

```text
public-net
private-net
lab-router
jenkins-controller
jenkins-agent-01
postgresql
```

## Validation after apply

On `lab-host`:

```bash
source /opt/openstack-client-venv/bin/activate
source /etc/kolla/admin-openrc.sh

openstack network show openshift-net
openstack subnet show openshift-subnet
openstack router show lab-router
openstack flavor show okd.control
openstack security group show openshift-nodes
openstack security group show okd-lb
openstack server show okd-lb
openstack port list --server okd-lb
openstack floating ip list
```

Expected key values:

```text
openshift-net CIDR  : 10.20.0.0/24
subnet gateway      : 10.20.0.1
okd.control         : 4 vCPU / 16384 MiB / 100 GiB
okd-lb fixed IP     : 10.20.0.10
okd-lb status       : ACTIVE
```

From the HCP Terraform outputs, record the dynamically allocated `okd-lb`
floating IP only for validation. Daily rebuild automation must discover it at
runtime rather than hard-code it.

## Daily rebuild model

This foundation remains fully reproducible:

```text
Terraform AWS apply
  -> Terraform OpenStack apply
     -> openshift-net + flavor + SGs + okd-lb recreated
        -> future make configure-lab discovers okd-lb FIP
           -> Ansible configures DNS/HAProxy
           -> OpenShift installer/bootstrap orchestration continues
```

No runtime floating IP or generated OpenShift installation artifact is committed
to Git.

## Next phase

The next implementation step is the `okd-lb` configuration layer:

```text
Ansible role okd_lb
  -> DNS
  -> HAProxy
  -> private Ignition HTTP endpoint
  -> runtime discovery integrated into make configure-lab
```

Only after that layer is validated will the bootstrap and compact control-plane
VMs be created.
