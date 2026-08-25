# PostgreSQL Ansible configuration runbook

## Goal

Step 21 turns the Terraform-created `postgresql` VM into a reproducible database
service while keeping state on the attached Cinder volume.

```text
ops-runner
   |
   | Ansible over management Floating IP
   v
postgresql VM 10.10.0.40
   |
   +-- Nova root
   |   -> Ubuntu / packages / /etc/postgresql
   |
   +-- Cinder volume
       -> ext4 label postgresql-data
       -> mounted at /var/lib/postgresql
       -> PostgreSQL 16 cluster data
```

The role order is deliberate:

```text
common_linux
    ↓
persistent_volume
    ↓
mount Cinder at /var/lib/postgresql
    ↓
postgresql package install
    ↓
cluster initialized directly on Cinder
```

Mounting first prevents PostgreSQL from creating database state on the disposable
Nova root disk and then hiding that state under a later mount.

## Database baseline

Step 21 creates:

```text
Database        portfolio
Owner role      portfolio_owner (NOLOGIN)
Login role      portfolio_app
Schema          portfolio
Authentication  SCRAM-SHA-256
Network         10.10.0.0/24 only
```

`portfolio_app` receives only `CONNECT` on the database and `USAGE,CREATE` on the
application schema. The owner role remains non-login. The later PostgreSQL
hardening step can split migration and runtime identities further without
changing the Step 21 persistence model.

## Configuration files

Ansible owns:

```text
/etc/postgresql/16/main/conf.d/99-private-banking-lab.conf
/etc/postgresql/16/main/pg_hba.conf
```

The drop-in config sets the private listener, SCRAM password encryption and the
logging baseline. `pg_hba.conf` allows the `portfolio_app` login to the
`portfolio` database from `10.10.0.0/24`; local PostgreSQL administration keeps
peer authentication through the Unix socket.

## Password lifecycle

The application password is never committed to Git and is not stored in
Terraform state.

On the first `make configure-postgresql`, Ansible running on `ops-runner`:

```text
SSM parameter exists?
   |
   +-- yes -> read SecureString
   |
   +-- no  -> generate 40-char random value
              -> write SecureString once
```

Parameter path:

```text
/private-banking-platform-lab/postgresql/portfolio-app-password
```

The AWS Terraform layer grants the ops-runner IAM role access only to that
specific parameter. Apply the AWS Terraform patch before running Step 21 for the
first time.

## Commands

Normal daily convergence remains one command:

```bash
make configure-lab
```

For PostgreSQL-only troubleshooting:

```bash
make configure-postgresql POSTGRESQL_FLOATING_IP=192.168.250.x
```

If the Floating IP is not known:

```bash
POSTGRESQL_FIP="$(./scripts/discover-openstack-floating-ip.sh postgresql)"
make configure-postgresql POSTGRESQL_FLOATING_IP="$POSTGRESQL_FIP"
```

## Validation

The playbook itself fails unless all of these are true:

```text
Cinder mounted at /var/lib/postgresql
PostgreSQL data_directory = /var/lib/postgresql/16/main
PostgreSQL ready on 10.10.0.40:5432
portfolio database exists
portfolio_app authenticates with SCRAM over the private interface
```

Useful inspection commands inside the VM:

```bash
findmnt /var/lib/postgresql
lsblk
sudo -u postgres psql -Atqc 'SHOW data_directory;'
sudo -u postgres psql -Atqc 'SHOW listen_addresses;'
sudo -u postgres psql -Atqc 'SHOW password_encryption;'
sudo -u postgres psql -Atqc '\\du'
sudo -u postgres psql -Atqc '\\l'
sudo ss -lntp | grep ':5432'
sudo journalctl -u postgresql --no-pager -n 100
sudo ls -lah /var/log/postgresql
```

The database is not exposed through `edge-gateway`; application traffic still
has to cross the private OpenStack network and pass both the Neutron Security
Group and `pg_hba.conf`.
