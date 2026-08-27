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

## OKD edge configuration layer

After the Terraform foundation exists, `make configure-lab` now discovers the
runtime Floating IP of `okd-lb` and converges it with Ansible. The fixed service
IP remains `10.20.0.10`; the Floating IP is management-only and may change on
every daily rebuild.

The canonical logical cluster values live in:

```text
platform/openshift/cluster-config.yml
```

This keeps the DNS/LB configuration and the future installer/bootstrap
orchestration aligned on the same names and fixed addresses.

Ansible configures three services on `okd-lb`:

```text
dnsmasq-base via private-banking-okd-dns.service
  53/udp + 53/tcp
  api.okd.lab.test       -> 10.20.0.10
  api-int.okd.lab.test   -> 10.20.0.10
  *.apps.okd.lab.test    -> 10.20.0.10
  bootstrap.okd.lab.test -> 10.20.0.11
  okd-01.okd.lab.test    -> 10.20.0.21
  okd-02.okd.lab.test    -> 10.20.0.22
  okd-03.okd.lab.test    -> 10.20.0.23

HAProxy
  6443  -> bootstrap + three control planes (Kubernetes API)
  22623 -> bootstrap + three control planes (Machine Config Server)
  443   -> three control planes (compact-cluster HTTPS ingress)
  80    -> three control planes (compact-cluster HTTP ingress)

Nginx
  8080  -> private runtime Ignition document root
```

The HAProxy backends are intentionally DOWN before bootstrap/control-plane VMs
exist. That is expected. This phase validates the front-end listeners and DNS;
the backends become healthy only during the next installation phase.

The future bootstrap removal workflow will also remove the bootstrap backend
from ports 6443 and 22623 after `bootstrap-complete`.

### Daily rebuild experience

The operator workflow stays simple:

```text
Terraform AWS apply
  -> Terraform OpenStack apply
     -> make configure-lab
        -> discover okd-lb FIP
        -> Ansible installs/configures dnsmasq + HAProxy + Nginx
        -> validate DNS + listeners + Ignition health endpoint
```

A direct one-service retry is also available:

```bash
make configure-okd-lb OKD_LB_FLOATING_IP=192.168.250.x
```

Normally this override is not needed because `make configure-lab` discovers the
Floating IP automatically.

### Validation on okd-lb

```bash
sudo systemctl status private-banking-okd-dns haproxy nginx --no-pager
sudo ss -lntup | grep -E ':(53|80|443|6443|22623|8080)\\b'

dig @10.20.0.10 api.okd.lab.test +short
dig @10.20.0.10 api-int.okd.lab.test +short
dig @10.20.0.10 smoke.apps.okd.lab.test +short
dig @10.20.0.10 bootstrap.okd.lab.test +short
dig @10.20.0.10 okd-01.okd.lab.test +short
dig @10.20.0.10 -x 10.20.0.21 +short

curl -fsS http://10.20.0.10:8080/healthz
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo dnsmasq --test --conf-file=/etc/private-banking-okd/dnsmasq.conf
sudo nginx -t
```

Expected DNS results:

```text
api/api-int/wildcard apps -> 10.20.0.10
bootstrap                 -> 10.20.0.11
okd-01                    -> 10.20.0.21
reverse 10.20.0.21        -> okd-01.okd.lab.test.
```

## Pinned installer and machine-OS prerequisite layer

After the DNS/LB edge has converged, the lab now prepares the installer-side
prerequisites automatically with:

```bash
make prepare-okd-installation-prereqs
```

The pinned release lives in `platform/openshift/cluster-config.yml`. The
matching `openshift-install`, `oc`, `kubectl` binaries are installed on
`ops-runner`, and the installer's own CoreOS stream metadata is used to import
the matching CentOS Stream CoreOS OpenStack QCOW2 image into Glance.

No bootstrap/control-plane VM is created in this layer. See
`docs/runbooks/openshift-installer-prerequisites.md` for the lifecycle and daily
rebuild behavior.
