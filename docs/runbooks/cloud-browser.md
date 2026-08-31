# Temporary AWS cloud browser

Use this workstation when the local/corporate Mac must only display a remote
session while the actual browser and Internet connection originate in AWS.

## Design

```text
Mac browser
  |
  | AWS Console / Systems Manager Fleet Manager
  v
Windows EC2 (t3.small)
  |
  | Chrome
  | source IPv4 = dedicated Elastic IP
  v
public ALB :443
  |
  v
edge-gateway -> Jenkins / Horizon / OpenShift
```

The Windows instance exposes **no inbound TCP ports**. Fleet Manager uses the
outbound SSM channels, so TCP/3389 is not opened in the EC2 security group.

The Elastic IP is deliberately stable. Terraform adds its `/32` to the public
ALB HTTP/HTTPS ingress rules. Public websites reached from Chrome see this EIP
as the IPv4 source address.

## Enable

Create a local, ignored tfvars file so later Terraform applies do not
accidentally remove the browser while you still need it:

```bash
cd infrastructure/terraform/aws
cat > cloud-browser.auto.tfvars <<'VARS'
cloud_browser_enabled = true
VARS

terraform init -reconfigure
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Get the fixed source IP and instance ID:

```bash
terraform output cloud_browser
```

Wait until SSM reports the instance online:

```bash
eval "$(terraform output -raw cloud_browser_ssm_check_command)"
```

The Windows password is normally generated a few minutes after launch. Retrieve
it with:

```bash
eval "$(terraform output -raw cloud_browser_password_command)"
```

The username is:

```text
Administrator
```

Then in the AWS console open:

```text
Systems Manager -> Fleet Manager -> Managed nodes
-> private-banking-platform-lab-cloud-browser
-> Node actions -> Connect -> Remote desktop
```

Log in as `Administrator` with the decrypted password and open Chrome. The
browser can then use:

```text
https://jenkins.lab.talelkarimchebbi.com
https://cloud.lab.talelkarimchebbi.com
https://console-openshift-console.apps.okd.lab.talelkarimchebbi.com
```

## Disable / save cost

When finished, remove the local enable file and apply again:

```bash
cd infrastructure/terraform/aws
rm -f cloud-browser.auto.tfvars
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform then removes the Windows instance, its root EBS volume, its EIP and
the two ALB allow rules. This leaves the rest of the lab unchanged.
