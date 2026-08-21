# Daily lab rebuild

The lab is intentionally destroyed when it is not being used to reduce AWS/EBS cost. The daily rebuild keeps provisioning and configuration as separate phases.

## Rebuild order

1. Apply the AWS Terraform stack.
2. Apply the OpenStack Terraform workspace.
3. On `ops-runner`, from the repository root, run:

```bash
make configure-lab
```

`configure-lab` is the single configuration/convergence entry point. It currently discovers the Jenkins Floating IP, configures the Jenkins controller with Ansible, then configures the edge gateway/Nginx with Ansible.

Future workload playbooks (starting with the Jenkins build agent) must be added behind this target so the daily operator workflow stays one command.

## Expected operator workflow

```text
Terraform AWS apply
      ↓
Terraform OpenStack apply
      ↓
ops-runner
      ↓
make configure-lab
      ↓
LAB CONFIGURATION READY
```

The repository is cloned automatically by the `ops-runner` cloud-init under:

```text
/home/ubuntu/workspace/private-banking-platform-lab
```

so a newly recreated runner should not require a manual `git clone` before convergence.

## Floating-IP discovery

The `ops-runner` has the OpenStack client tooling installed, but the Kolla admin `clouds.yaml` deliberately remains on `lab-host` under `/data/openstack/secrets/clouds.yaml`.

To avoid copying OpenStack admin credentials to `ops-runner`, `scripts/discover-openstack-floating-ip.sh`:

1. retrieves the existing AWS lab SSH key temporarily from SSM Parameter Store;
2. connects over the private AWS network from `ops-runner` to `lab-host`;
3. uses the OpenStack CLI and the local `kolla-admin` cloud on `lab-host`;
4. resolves the Jenkins networking object and its associated Floating IP in the provider CIDR `192.168.250.0/24`;
5. returns only that runtime address to `ops-runner`;
6. removes the temporary SSH key when the script exits.

The discovery path must fail with a useful error if SSH/OpenStack access itself is broken; it must not silently turn every control-plane error into a long Floating-IP wait.

For troubleshooting only, automatic discovery can be bypassed:

```bash
make configure-lab JENKINS_FLOATING_IP=192.168.250.123
```

## Success criteria

A successful daily rebuild ends with:

```text
Jenkins            READY
Edge gateway       READY
Jenkins FIP        192.168.250.x
LAB CONFIGURATION READY
```

At that point Jenkins must be reachable through the edge gateway and the controller service must be active.
