# Persistent public-ingress foundation

This Terraform root is intentionally **not** part of the daily lab destroy.
It owns only long-lived public-ingress prerequisites:

- lookup of the existing `talelkarimchebbi.com` Route53 hosted zone;
- one ACM public certificate for `*.lab.talelkarimchebbi.com`;
- one SAN for `*.apps.okd.lab.talelkarimchebbi.com`;
- ACM DNS-validation records required for automatic renewal.

Apply it once before the normal ephemeral AWS Terraform root:

```bash
terraform init
terraform plan
terraform apply
```

The normal `infrastructure/terraform/aws` state reads this state and creates
an ephemeral ALB plus Route53 aliases on every daily lab rebuild.
