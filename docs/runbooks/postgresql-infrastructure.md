# PostgreSQL OpenStack infrastructure runbook

## Goal

Step 20 creates the PostgreSQL infrastructure only. PostgreSQL software and the
filesystem/data-directory configuration remain owned by Ansible in step 21.

```text
ops-runner
   |
   | SSH management through provider/Floating IP
   v
postgresql
10.10.0.40
   |
   +-- Nova root disk (Ubuntu 24.04)
   |
   +-- Cinder data volume (20 GiB)
       -> PostgreSQL data in step 21
```

The VM uses the reusable `lab.medium` flavor:

```text
2 vCPU / 4 GiB RAM / 20 GiB Nova root disk
```

The attached Cinder volume is separate from the root disk so database state can
be treated as persistent service data rather than disposable operating-system
state.

## Network and security model

The VM receives:

```text
fixed IP:        10.10.0.40
management FIP:  dynamically allocated from 192.168.250.100-199
security groups: lab-management + postgresql
```

The Floating IP is not an Internet publication mechanism in this lab. It exists
because the current ops-runner administration path reaches OpenStack workloads
through the provider network and Neutron Floating IP DNAT.

`lab-management` keeps the existing SSH/ICMP administration policy. The new
`postgresql` Security Group allows TCP/5432 only from the private OpenStack
network:

```text
10.10.0.0/24 -> postgresql:5432   ALLOWED
172.31.16.0/20 -> postgresql:5432 NOT ALLOWED
edge-gateway -> postgresql:5432   NOT ALLOWED
Internet -> postgresql:5432       NOT ALLOWED
```

Applications deployed later on the private OpenStack network can therefore
reach PostgreSQL, while the edge gateway never publishes the database port.

## Expected Terraform resources

A Step 20 OpenStack plan should add resources equivalent to:

```text
postgresql                         Neutron Security Group
postgresql private ingress rule   TCP/5432 from 10.10.0.0/24
postgresql-port                    Neutron port at 10.10.0.40
postgresql                         Nova VM
postgresql-data                    20 GiB Cinder volume
volume attachment                 Cinder -> Nova
one Floating IP                   management path only
```

The existing `compute-instance` module is reused rather than creating a
PostgreSQL-specific VM implementation.

## Validation after apply

On the OpenStack host:

```bash
source /opt/openstack-client-venv/bin/activate
source /etc/kolla/admin-openrc.sh

openstack server show postgresql
openstack port show postgresql-port
openstack volume show postgresql-data
openstack security group show postgresql
openstack floating ip list --port "$(openstack port show postgresql-port -f value -c id)"
```

Expected results:

```text
server status       ACTIVE
fixed IP            10.10.0.40
Cinder volume       attached
Security Groups     lab-management + postgresql
Floating IP         associated with postgresql-port
```

Verify the database rule itself:

```bash
openstack security group rule list postgresql
```

There must be a TCP/5432 ingress rule whose remote CIDR is `10.10.0.0/24`.

From the ops-runner, discover the management Floating IP with the existing
helper:

```bash
POSTGRESQL_FIP="$(./scripts/discover-openstack-floating-ip.sh postgresql)"
echo "$POSTGRESQL_FIP"

ssh -i /home/ubuntu/.ssh/private-banking-openstack-workloads \
  ubuntu@"$POSTGRESQL_FIP"
```

Inside the VM:

```bash
hostname
ip address
ip route
lsblk
```

At this stage the Cinder disk must be visible but must **not** be formatted or
mounted manually. Step 21 will reuse the existing `persistent_volume` Ansible
role so filesystem creation and mounting remain idempotent and automated.

Step 21 implementation and validation are documented in
`docs/runbooks/postgresql-configuration.md`.
