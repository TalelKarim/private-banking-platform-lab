# Jenkins controller provisioning runbook

## Goal

Configure the Terraform-created `jenkins-controller` VM from the AWS `ops-runner` without manual mutation of the guest.

The automation owns:

- workload Ansible inventory and SSH access;
- Ubuntu baseline configuration;
- safe discovery, formatting and persistent mounting of the attached Cinder data disk;
- Jenkins LTS installation on Java 21;
- `JENKINS_HOME` on Cinder;
- one local administrator bootstrapped from AWS SSM Parameter Store;
- disabled anonymous access and disabled legacy inbound agent TCP port;
- baseline Jenkins plugins;
- idempotent validation.

## Data path

```text
Nova root disk (/dev/vda)
└── Ubuntu + Jenkins binaries

Cinder data disk (first non-root disk; labelled jenkins-data)
└── /var/lib/jenkins
    └── JENKINS_HOME
```

The volume role formats a disk only when `blkid` proves that it has no filesystem. If there is more than one non-root disk, or an unexpected filesystem is present, the playbook fails rather than guessing.

## Required secret

Create the Jenkins administrator password once from an operator machine with AWS credentials. Keep the secret out of Git and Terraform state.

```bash
JENKINS_ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"

aws ssm put-parameter \
  --region eu-south-2 \
  --name /private-banking-platform-lab/jenkins/admin-password \
  --type SecureString \
  --value "$JENKINS_ADMIN_PASSWORD" \
  --overwrite

unset JENKINS_ADMIN_PASSWORD
```

The ops-runner IAM role is restricted to `ssm:GetParameter` for this exact parameter and retrieves it at playbook runtime. The clear-text password is marked `no_log` and is not committed to Git.

## Apply AWS changes

The hostname/IAM change belongs to the AWS Terraform layer.

```bash
terraform -chdir=infrastructure/terraform/aws fmt -check
terraform -chdir=infrastructure/terraform/aws validate
terraform -chdir=infrastructure/terraform/aws plan
terraform -chdir=infrastructure/terraform/aws apply
```

Important: `ops-runner` has `user_data_replace_on_change = true`; changing its cloud-init replaces that stateless instance. Its public/private IP can therefore change. The HCP agent and workload SSH key are restored automatically at bootstrap.

The lab-host is not replaced by its user-data change. Its current hostname is converged by the existing Ansible bootstrap because the `common_linux` role now sets `lab-host`.

## Sync the repository to the ops-runner

Use the normal Git workflow so the exact committed automation reaches `/home/ubuntu/workspace` (or another checkout) on the ops-runner. Do not copy private keys into the repository.

Validate the runner bootstrap:

```bash
hostname
systemctl is-active tfc-agent
ls -l /home/ubuntu/.ssh/private-banking-openstack-workloads
```

Expected hostname:

```text
ops-runner
```

Expected key mode:

```text
-rw-------
```

## Obtain the current Jenkins Floating IP

Read the `jenkins_controller.floating_ip` output from the OpenStack Terraform workspace / HCP Terraform run output.

Example:

```text
192.168.250.123
```

The address is passed at runtime instead of being committed to inventory, so recreating the Floating IP does not require a Git change.

## Configure Jenkins

From the repository checkout on the ops-runner:

```bash
make configure-jenkins JENKINS_FLOATING_IP=192.168.250.123
```

The wrapper first runs `ansible.builtin.ping`. Only if SSH succeeds does it execute `playbooks/configure-jenkins.yml`.

## What the playbook does

```text
ops-runner
   │
   │ SSH using /home/ubuntu/.ssh/private-banking-openstack-workloads
   ▼
jenkins-controller
   │
   ├── common_linux
   │   └── hostname + packages + chrony
   │
   ├── persistent_volume
   │   └── Cinder -> ext4 -> /var/lib/jenkins -> /etc/fstab
   │
   └── jenkins_controller
       ├── Java 21
       ├── Jenkins LTS repository
       ├── Jenkins package/service
       ├── setup wizard disabled
       ├── local admin from SSM
       ├── anonymous access disabled
       ├── inbound agent TCP port disabled
       └── baseline plugins
```

## Validation

On the Jenkins VM through SSH:

```bash
hostname
findmnt /var/lib/jenkins
lsblk -f
systemctl is-active jenkins
systemctl is-enabled jenkins
java -version
ss -lntp | grep ':8080'
sudo journalctl -u jenkins --no-pager -n 100
```

Expected hostname:

```text
jenkins-controller
```

Expected service state:

```text
active
enabled
```

`findmnt /var/lib/jenkins` must show the Cinder-backed filesystem labelled `jenkins-data`, not `/dev/vda1`.

Validate persistence:

```bash
sudo touch /var/lib/jenkins/.cinder-persistence-test
sudo reboot
```

Reconnect and verify:

```bash
test -f /var/lib/jenkins/.cinder-persistence-test && echo OK
findmnt /var/lib/jenkins
systemctl is-active jenkins
```

Remove the test marker afterwards:

```bash
sudo rm -f /var/lib/jenkins/.cinder-persistence-test
```

## Validate idempotence

Run the same command a second time:

```bash
make configure-jenkins JENKINS_FLOATING_IP=192.168.250.123
```

The second run must not format the Cinder volume, must preserve Jenkins data, and should report only zero or strictly justified changes.

## Secure browser access for the lab

Do not broaden the Jenkins Security Group just to reach the UI from the Internet. Use SSH port forwarding through the existing management path.

From the repository root on the operator Mac, use separate identities for the AWS jump host and the OpenStack workload:

```bash
ssh \
  -o "ProxyCommand=ssh -i infrastructure/terraform/aws/.keys/private-banking-platform-lab.pem -W %h:%p ubuntu@<OPS_RUNNER_PUBLIC_IP>" \
  -i "$HOME/.ssh/private-banking-openstack-workloads" \
  -L 8080:127.0.0.1:8080 \
  ubuntu@<JENKINS_FLOATING_IP>
```

Keep that SSH session open and browse to `http://127.0.0.1:8080`. This does not require exposing Jenkins port 8080 to the Internet or to the AWS management subnet.

The initial administrator username is:

```text
admin
```

Read the password from SSM only when needed; do not store it in shell history or Git.
