# Private Banking Platform Lab

A reproducible private-banking platform lab built in layers:

```text
AWS infrastructure
  -> lab-host (nested KVM + OpenStack/Kolla)
  -> ops-runner (HCP Terraform Agent + Ansible administration)
  -> edge-gateway (Nginx HTTP/HTTPS ingress)
      -> Terraform OpenStack networks/VMs/volumes
          -> Ansible workload convergence
              -> Jenkins CI/CD execution plane
                  -> PostgreSQL / OpenShift / applications / observability
```

## Architecture and operating model

The lab is built as separate provisioning, configuration and platform layers.

- Terraform AWS creates `lab-host`, `ops-runner` and `edge-gateway` with the required IAM, Security Groups, routes and storage.
- `lab-host` can boot from the validated Golden AMI, which avoids reinstalling the complete Kolla/OpenStack control plane during the daily lab rebuild.
- Kolla-Ansible provides the OpenStack all-in-one control plane on the nested KVM host.
- HCP Terraform stores the OpenStack state/run history while the HCP Terraform Agent executes OpenStack runs on `ops-runner`.
- `ops-runner` is the administration plane for the lab: Terraform/OpenStack CLI, Ansible, workload SSH material from SSM, EC2 Instance Connect and the project repository cloned under `/home/ubuntu/workspace/private-banking-platform-lab` at bootstrap.
- Terraform OpenStack owns the provider network `192.168.250.0/24`, private network `10.10.0.0/24`, router, security groups, reusable flavors/images, explicit workload ports, Floating IPs and Cinder volumes.
- Terraform explicitly waits for the Neutron router path before creating workloads that need Floating IPs, avoiding the first-run `ExternalGatewayForFloatingIPNotFound` race.
- `jenkins-controller` is provisioned on `10.10.0.20` with a dedicated persistent Cinder data volume for `JENKINS_HOME`.
- Ansible installs and configures Jenkins LTS on Java 21, bootstraps the administrator from SSM, disables anonymous access and installs the baseline plugins.
- `edge-gateway` exposes the web ingress through its AWS Elastic IP; Ansible installs Nginx and proxies Jenkins traffic to its OpenStack Floating IP.
- `make configure-lab`, executed from `ops-runner`, is the single convergence entry point for the configuration layer. It discovers the Jenkins controller, worker and PostgreSQL Floating IPs, converges both Jenkins nodes, configures the Cinder-backed PostgreSQL service plus its logical-backup timer, verifies the database baseline, and then converges the edge gateway.

## Daily rebuild workflow

The normal lab rebuild is intentionally reduced to three operator actions:

```text
1. Terraform AWS apply
   -> lab-host + ops-runner + edge-gateway

2. Terraform OpenStack apply
   -> networks + router + Jenkins controller/worker + PostgreSQL VM + required storage/Floating IPs

3. On ops-runner:
   make configure-lab
   -> Jenkins controller + worker + PostgreSQL + Nginx convergence
```

See `docs/runbooks/daily-lab-rebuild.md` for the exact procedure.

## Main commands

OpenStack host/control-plane lifecycle:

```bash
make prepare-openstack
make deploy-openstack
make validate-openstack
```

Or run the complete chain when rebuilding OpenStack itself:

```bash
make openstack-up
```

Daily workload convergence from `ops-runner`:

```bash
make configure-lab
```

Individual configuration targets remain available for troubleshooting:

```bash
make configure-jenkins JENKINS_FLOATING_IP=192.168.250.x
make configure-jenkins-worker \
  JENKINS_FLOATING_IP=192.168.250.x \
  JENKINS_WORKER_FLOATING_IP=192.168.250.y
make test-jenkins-worker
make configure-postgresql POSTGRESQL_FLOATING_IP=192.168.250.z
make backup-postgresql
make list-postgresql-backups
make test-postgresql-restore
make restore-postgresql BACKUP=latest TARGET_DB=portfolio_restore_manual
make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x
make configure-openshift-cicd
make test-openshift-cicd
make configure-demo-3tier
make deploy-demo-3tier
make test-demo-3tier
```

## demo-3tier learning workload

The first real OpenShift workload is under `applications/demo-3tier/`. It uses raw YAML and a Jenkins-managed build/deploy pipeline to make the Kubernetes/OpenShift request path visible before introducing Helm. The public lab URL is `https://demo.apps.okd.lab.talelkarimchebbi.com`; it reuses the existing wildcard Route53/ACM/ALB/edge-gateway ingress and remains limited by the ALB lab-client Security Group. See `docs/openshift-demo-3tier-phase3.md`.

## Repository structure

```text
private-banking-platform-lab/
├── infrastructure/
│   ├── terraform/
│   │   ├── aws/
│   │   └── openstack/
│   ├── ansible/
│   │   ├── inventories/
│   │   ├── playbooks/
│   │   └── roles/
│   └── openstack/
│       └── kolla/
├── applications/
│   ├── demo-3tier/
│   ├── portfolio-java/
│   └── risk-engine-dotnet/
├── cicd/
│   └── smoke-tests/
├── scripts/
├── docs/
└── Makefile
```

## Platform build order

The platform follows `docs/roadmap.md` in infrastructure-first order:

1. Jenkins controller and dedicated build worker;
2. PostgreSQL VM, Ansible configuration, persistence, backup and restore;
3. OpenShift/OKD infrastructure, node preparation, cluster installation and platform layer;
4. real Spring Boot `portfolio-java` and .NET `risk-engine-dotnet` applications;
5. container images, registry, Helm and Jenkins CI/CD;
6. Prometheus, Grafana, centralised logs, alerting, hardening and resilience scenarios.

The tiny Java/.NET projects under `cicd/smoke-tests/` are infrastructure probes only; they do not start the application implementation phase.

See `docs/roadmap.md` for the complete fixed A-to-Z plan.

## Workload runbooks

- Daily rebuild: `docs/runbooks/daily-lab-rebuild.md`
- Jenkins controller: `docs/runbooks/jenkins-controller.md`
- Jenkins worker: `docs/runbooks/jenkins-worker.md`
- PostgreSQL infrastructure: `docs/runbooks/postgresql-infrastructure.md`
- PostgreSQL configuration: `docs/runbooks/postgresql-configuration.md`
- PostgreSQL backup/restore: `docs/runbooks/postgresql-backup-restore.md`
- Edge gateway: `docs/runbooks/edge-gateway.md`
- OpenStack workload access: `docs/runbooks/openstack-workload-access.md`
