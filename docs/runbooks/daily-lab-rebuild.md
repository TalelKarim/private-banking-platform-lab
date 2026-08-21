# Daily lab rebuild

The lab is intentionally destroyed when it is not being used to reduce AWS/EBS cost. The daily rebuild keeps provisioning and configuration as separate phases.

## Rebuild order

1. Apply the AWS Terraform stack.
2. Apply the OpenStack Terraform workspace.
3. On `ops-runner`, from the repository root, run:

```bash
make configure-lab
```

`configure-lab` is the single configuration/convergence entry point. It currently discovers the Jenkins floating IP, configures the Jenkins controller with Ansible, then configures the edge gateway/Nginx with Ansible.

Future workload playbooks should be added behind this target so the daily operator workflow stays one command.

## Floating-IP discovery

The `ops-runner` already has an OpenStack CLI installed, but the Kolla admin `clouds.yaml` deliberately remains on `lab-host` under `/data/openstack/secrets/clouds.yaml`.

To avoid copying OpenStack admin credentials to `ops-runner`, `scripts/discover-openstack-floating-ip.sh` retrieves the existing AWS lab SSH key temporarily from SSM Parameter Store, SSHes from `ops-runner` to the private IP of `lab-host`, executes the OpenStack CLI on `lab-host` using the local `kolla-admin` cloud, extracts the workload address belonging to `192.168.250.0/24`, then deletes the temporary SSH key when the script exits.

For troubleshooting only, automatic discovery can be bypassed:

```bash
make configure-lab JENKINS_FLOATING_IP=192.168.250.123
```
