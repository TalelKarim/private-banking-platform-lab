# Ready AMI workflow

This workflow is a fast checkpoint workflow for day-to-day lab work. It is
intentionally different from the clean `prepare-golden-ami` workflow.

- Clean Golden AMI: OpenStack control plane only, workload-free baseline.
- Ready AMI: current lab-host state preserved, including OpenStack workloads,
  OKD VMs, Jenkins, registry storage, Cinder volumes and deployed demo state.

Use the ready workflow when the lab foundation is already validated and the next
work is mainly application YAML, Helm, Jenkins pipelines, Java/.NET services,
monitoring or GitOps.

## 1. Validate the current live lab

From the ops-runner or your normal control point:

```bash
make test-demo-3tier
make test-openshift-cicd
make validate-openstack
```

Also validate the public ingress path:

```bash
curl -kI https://jenkins.talelkarimchebbi.com
curl -kI https://cloud.talelkarimchebbi.com
curl -kI https://demo.apps.okd.lab.talelkarimchebbi.com
```

Do not bake a broken state. The ready AMI will preserve the current state as-is.

## 2. Bake the lab-host ready AMI

From the repository root on the Mac:

```bash
make bake-lab-ready-ami
```

The script reads the current lab-host instance ID, AWS region and fixed private IP
from Terraform outputs. It stops the EC2 instance, creates an AMI containing the
three EBS snapshots (root, `/data`, Cinder), waits for the AMI to become available
and then restarts the source instance if it was running.

The ready AMI preserves the nested OpenStack state stored under `/data` and the
Cinder LVM EBS device.

## 3. Bake the edge gateway ready AMI

After the edge gateway has been configured with Ansible and Nginx is healthy:

```bash
make bake-edge-gateway-ami
```

The script reads the edge gateway instance ID and fixed private IP from Terraform
outputs. It creates a root-disk AMI of the already configured gateway.

The edge gateway AMI preserves the installed packages and Nginx reverse-proxy
configuration. If Jenkins or okd-lb floating IPs change later, rerun
`make configure-edge-gateway` to refresh Nginx upstreams.

## 4. Activate both AMIs for future Terraform launches

Use the AMI IDs printed by both bake commands:

```bash
make activate-ready-amis \
  LAB_HOST_AMI_ID=ami-xxxxxxxxxxxxxxxxx \
  EDGE_GATEWAY_AMI_ID=ami-yyyyyyyyyyyyyyyyy
```

This writes `infrastructure/terraform/aws/ready.auto.tfvars`, which is ignored by
Git. It sets:

```hcl
golden_ami_id       = "ami-..." # lab-host ready AMI with 3 EBS snapshots
edge_gateway_ami_id = "ami-..." # edge-gateway root AMI
```

## 5. Recreate from the ready AMIs

```bash
cd infrastructure/terraform/aws
terraform plan
terraform apply
```

Terraform still owns the AWS resources: EC2 instances, security groups, ALB,
Route53 aliases, EIPs, IAM, routes and key material. The AMIs only accelerate the
instance filesystem/state bootstrap.

After apply, wait for cloud-init on both Linux hosts:

```bash
terraform output -raw bootstrap_log_command
terraform output -raw edge_gateway_bootstrap_log_command
```

If OpenStack guests do not automatically resume, use the existing lightweight
recovery path instead of full `configure-lab`:

```bash
make recover-openstack-guests
make test-demo-3tier
```

## Important constraints

- Keep `openstack_host_private_ip` stable. Kolla/OpenStack endpoints are baked
  with that address.
- Keep `edge_gateway_private_ip` stable. Security groups, routing and Ansible
  inventory expect it.
- The lab-host ready AMI must contain exactly three EBS snapshots: root, `/data`,
  and Cinder.
- The edge gateway ready AMI must contain exactly one EBS snapshot: root.
- Ready AMIs are checkpoints, not clean immutable product images. Re-bake them
  after major changes that you want to keep as the new fast-start state.
- Do not use the ready AMI as a DR strategy for production. It is a lab speed-up
  mechanism.
