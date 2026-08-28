# Public lab ingress: Route53 -> ALB/ACM -> edge -> private platform

## Naming

The canonical DNS values live in `platform/openshift/cluster-config.yml`:

- public zone: `talelkarimchebbi.com`
- lab suffix: `lab.talelkarimchebbi.com`
- OKD cluster: `okd`

Published browser endpoints:

- `https://jenkins.lab.talelkarimchebbi.com`
- `https://cloud.lab.talelkarimchebbi.com`
- `https://*.apps.okd.lab.talelkarimchebbi.com`

The OKD API remains private. Nodes resolve `api.okd.lab.talelkarimchebbi.com`
to `10.20.0.10`; ops-runner maps the same FQDN to the current okd-lb floating
IP. No public Route53 record is created for the Kubernetes API.

## Persistent vs daily Terraform

`infrastructure/terraform/aws-global` is persistent and must **not** be part of
the nightly destroy. It looks up the existing Route53 zone and owns:

- ACM certificate `*.lab.talelkarimchebbi.com`;
- SAN `*.apps.okd.lab.talelkarimchebbi.com`;
- ACM DNS validation records.

Apply it once:

```bash
cd infrastructure/terraform/aws-global
terraform init
terraform plan
terraform apply
```

The normal `infrastructure/terraform/aws` state stays ephemeral. Every lab
rebuild it creates:

- internet-facing ALB;
- HTTP -> HTTPS redirect;
- HTTPS listener using the persistent ACM certificate;
- edge-gateway target group;
- Route53 aliases for Jenkins, Horizon and the OKD apps wildcard.

## Request path

```text
browser
  -> Route53
  -> public ALB :443 (ACM terminates browser TLS)
  -> edge-gateway Nginx :80
     -> jenkins.* -> Jenkins floating IP :8080
     -> cloud.*   -> lab-host private IP :80 (Horizon)
     -> *.apps.okd.* -> okd-lb floating IP :443
                        -> HAProxy
                        -> OpenShift Router
                        -> Route/Service/Pod
```

Nginx re-encrypts the OpenShift hop because standard OpenShift Routes such as
the console and OAuth redirect insecure HTTP to HTTPS. It sends SNI equal to the
original route hostname and intentionally does not validate the cluster-generated
internal ingress certificate; the public browser certificate is ACM on the ALB.

## First migration from lab.test

Changing `okd_base_domain` changes the cluster identity. Do not try to mutate an
already-installed `okd.lab.test` cluster in place. Recreate only the runtime OKD
machines/assets:

```bash
make destroy-okd-nodes
rm -rf .runtime/openshift/install .runtime/openshift/ignition-stubs
```

Then run the normal convergence after the AWS/OpenStack foundations are ready:

```bash
make configure-lab
```

The bootstrap lifecycle cleanup remains a separate OKD lifecycle step.

## Browser validation

After the ALB target becomes healthy and OKD reaches install-complete:

```bash
curl -I https://jenkins.lab.talelkarimchebbi.com
curl -I https://cloud.lab.talelkarimchebbi.com
curl -I https://console-openshift-console.apps.okd.lab.talelkarimchebbi.com
```

The ALB security group only accepts the configured lab client CIDR (by default
the public IPv4 detected during the AWS Terraform apply), so a public DNS record
does not make the lab UIs generally reachable from the Internet.
