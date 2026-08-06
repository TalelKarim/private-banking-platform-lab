# OpenStack deployment runbook

## Rebuild the AWS host after applying this changeset

The current EC2 was created with the previous large user-data. Because
`user_data_replace_on_change` is disabled, replace the EC2 once so the minimal
bootstrap becomes the real baseline. The persistent data EBS remains managed as
its own Terraform resource and is reattached.

```bash
cd infrastructure/terraform/aws
terraform init -upgrade -reconfigure
terraform fmt -recursive
terraform validate
terraform plan -replace=aws_instance.lab -out=tfplan
terraform apply tfplan
```

Wait for the minimal bootstrap:

```bash
sudo cloud-init status --wait --long
sudo tail -n 100 /var/log/private-banking-lab-bootstrap.log
```

The final marker must be present:

```text
=== Minimal private banking lab bootstrap completed ===
```

## Deploy OpenStack from the repository

Clone the repository on the EC2 data volume:

```bash
cd /data/repos
git clone <REPOSITORY_URL> private-banking-platform-lab
cd private-banking-platform-lab
```

Safe checkpoint flow:

```bash
make prepare-openstack
make deploy-openstack
make validate-openstack
```

One-command flow:

```bash
make openstack-up
```

## What the command does

1. Creates a project-local Ansible virtual environment.
2. Configures the AWS host and nested KVM prerequisites.
3. Creates a veth pair:
   - `os-ext`: handed to Neutron and attached to `br-ex` by Kolla.
   - `os-host`: keeps `192.168.250.1/24` on the Linux host.
4. NATs `192.168.250.0/24` out through the EC2 management interface.
5. Creates the `cinder-volumes` LVM volume group on the dedicated Cinder EBS.
6. Installs Kolla-Ansible `22.0.0` and renders `/etc/kolla`.
7. Runs `bootstrap-servers`, `prechecks`, `pull`, `deploy`, and `post-deploy`.
8. Validates the APIs and core services with `openstack --os-cloud kolla-admin`.

## Persistent secrets

These files are generated on the host and are intentionally absent from Git:

```text
/data/openstack/secrets/passwords.yml
/data/openstack/secrets/clouds.yaml
```

Back them up securely before destroying the persistent data volume.
