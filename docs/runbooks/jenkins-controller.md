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

The `ops-runner` cloud-init clones the project automatically to:

```text
/home/ubuntu/workspace/private-banking-platform-lab
```

Use normal `git pull` operations only when you need to refresh an already-running runner after pushing new automation. Do not copy private keys into the repository.

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

## Discover and configure Jenkins

For the normal daily rebuild, do not look up or copy the Jenkins Floating IP manually. From the repository checkout on `ops-runner`, run:

```bash
make configure-lab
```

The orchestrator discovers the current Jenkins Floating IP through `lab-host`, then passes it to the Jenkins and edge-gateway configuration wrappers.

For Jenkins-only troubleshooting, the lower-level target is still available:

```bash
make configure-jenkins JENKINS_FLOATING_IP=192.168.250.x
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

## Browser access

The normal browser path is now the dedicated edge gateway:

```text
Browser -> edge-gateway EIP:80 -> Nginx -> Jenkins Floating IP:8080 -> Jenkins
```

Use the Terraform output `edge_gateway_http_url` (or the future Jenkins DNS name once Route53/TLS is implemented). Do not expose Jenkins port `8080` directly to the Internet.

The initial administrator username is:

```text
admin
```

Read the password from SSM only when needed; do not store it in shell history or Git.
