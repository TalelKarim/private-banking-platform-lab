# Private Banking Platform Lab

A reproducible private-cloud / DevOps lab that runs a complete application platform on top of AWS, nested OpenStack and OKD/OpenShift.

The project is intentionally built in layers so every responsibility is visible:

```text
AWS
  -> EC2 lab-host / ops-runner / edge-gateway
      -> KVM + Kolla-Ansible
          -> OpenStack
              -> Nova / Neutron / Cinder / Glance
                  -> Jenkins + PostgreSQL + OKD VMs
                      -> OpenShift platform services
                          -> integrated registry + Cinder CSI
                              -> Helm workloads
                                  -> portfolio-java
                                  -> risk-engine-api
```

Git is the source of truth. Terraform creates infrastructure, Ansible converges systems and services, Jenkins performs CI/CD, Helm describes application releases, and `make configure-lab` is the single daily convergence entry point from the ops-runner.

---

## Current implemented architecture

### AWS foundation

Terraform AWS provides the physical lab foundation:

- `lab-host`: nested virtualization host for KVM + Kolla OpenStack;
- `ops-runner`: administration plane, HCP Terraform Agent, Ansible and operational tooling;
- `edge-gateway`: public Nginx ingress behind the AWS ALB/ACM path;
- IAM, Security Groups, routing, SSM parameters and EBS storage;
- Route53 records under `talelkarimchebbi.com`.

The lab-host uses dedicated EBS-backed storage for the host data layer and the Cinder LVM backend.

### OpenStack foundation

Kolla-Ansible runs OpenStack on the lab-host.

Main services include:

```text
Keystone
Nova
Neutron
Glance
Placement
Cinder
Heat
Horizon
Open vSwitch
```

Terraform OpenStack owns the durable workload foundation, including:

```text
private-net       10.10.0.0/24
openshift-net     10.20.0.0/24
public-net        192.168.250.0/24
lab-router
workload ports
Floating IPs
Security Groups
Cinder volumes
reusable images/flavors
```

The provider-network path is:

```text
OpenStack public-net
192.168.250.0/24
        |
      br-ex
        |
   os-ext <-> os-host
              192.168.250.1
                   |
               lab-host
                   |
                AWS VPC
```

### Persistent platform VMs

Current principal OpenStack workloads:

```text
jenkins-controller  10.10.0.20
jenkins-agent-01    10.10.0.30
postgresql          10.10.0.40
okd-lb              10.20.0.10
okd-01              10.20.0.21
okd-02              10.20.0.22
okd-03              10.20.0.23
```

Jenkins and PostgreSQL use Cinder-backed persistent data where required.

---

## OKD / OpenShift

The lab runs a compact three-control-plane OKD cluster.

Current pinned cluster release:

```text
4.22.0-okd-scos.8
```

Network model:

```text
machine network : 10.20.0.0/24
pod network     : 10.128.0.0/14
service network : 172.30.0.0/16
```

The cluster is installed as user-provisioned infrastructure on OpenStack.

The reusable platform layer includes:

- OpenStack Cinder CSI;
- default `cinder-standard` StorageClass;
- persistent OpenShift integrated registry;
- Jenkins ServiceAccount and namespace RBAC;
- Jenkins-to-OpenShift API access;
- Jenkins-to-integrated-registry image push path;
- Helm-based application deployment;
- immutable image deployment by digest.

Public application routes use the existing wildcard ingress under:

```text
*.apps.okd.lab.talelkarimchebbi.com
```

with the external path conceptually:

```text
browser
  -> Route53
  -> AWS ALB + ACM
  -> edge-gateway Nginx
  -> OpenStack / okd-lb
  -> OpenShift Ingress Router
  -> Route
  -> Service
  -> Pod
```

---

## Applications

### demo-3tier

The original learning workload validates the OpenShift application path, Jenkins image build/push and Helm deployment.

Public URL:

```text
https://demo.apps.okd.lab.talelkarimchebbi.com
```

### portfolio-java

Spring Boot / Java 21 API deployed in namespace `banking`.

Runtime path:

```text
Route
  -> Service portfolio-java:8080
  -> Spring Boot pods
  -> JDBC
  -> PostgreSQL VM 10.10.0.40:5432
  -> Cinder-backed database storage
```

Public URL:

```text
https://portfolio.apps.okd.lab.talelkarimchebbi.com
```

The Jenkins pipeline performs source checkout, Maven validation, Podman image build, push to the OpenShift integrated registry, ImageStream digest resolution, Helm deployment, rollout validation and smoke tests.

### risk-engine-api

ASP.NET Core / .NET 10 service under `applications/risk-engine-api`.

The local Docker Compose chain has been validated:

```text
risk-engine-api
   -> portfolio-java
      -> PostgreSQL
```

The OpenShift deployment automation is now implemented and integrated into the daily lab convergence.

Target runtime path:

```text
Route risk.apps.okd.lab.talelkarimchebbi.com
  -> Service risk-engine-api:8080
  -> ASP.NET Core pod
  -> http://portfolio-java:8080/
  -> Kubernetes/OpenShift Service DNS
  -> portfolio-java pods
  -> PostgreSQL VM 10.10.0.40:5432
```

The Risk Engine currently uses one replica because its latest-calculation store is process-local memory. Horizontal scaling should be enabled after that state is moved to a shared persistent store.

The complete OpenShift Risk Engine path is implemented in Git and is the next full rebuild validation step.

---

## CI/CD model

Both real applications follow the same deployment pattern:

```text
GitHub
   |
   v
Jenkins controller
   |
   v
jenkins-agent-01
   |
   +--> source checkout
   +--> application/container build
   +--> Podman
   +--> OpenShift integrated registry
   +--> ImageStream
   +--> resolve immutable sha256 digest
   +--> Helm upgrade --install
   +--> OpenShift rollout
   +--> smoke tests
```

The deployed image reference is pinned as:

```text
.../namespace/application@sha256:...
```

rather than a mutable `:latest` tag.

---

## Daily rebuild workflow

The operator workflow intentionally remains simple:

```text
1. Terraform AWS apply
       |
       v
   lab-host + ops-runner + edge-gateway

2. Terraform OpenStack apply
       |
       v
   durable OpenStack workload foundation

3. On ops-runner
       |
       v
   make configure-lab
```

Repository path on the ops-runner:

```text
/home/ubuntu/workspace/private-banking-platform-lab
```

Before convergence, update the checkout when needed:

```bash
git pull origin main
make configure-lab
```

`make configure-lab` currently orchestrates 27 stages, including:

```text
OpenStack guest recovery/runtime convergence
Jenkins controller
Jenkins worker
PostgreSQL
edge-gateway
okd-lb
OKD tooling/image/install assets
OKD nodes and installation
Cinder CSI
OpenShift integrated registry
Jenkins <-> OpenShift CI/CD bridge
portfolio-java configure/deploy/test
risk-engine-api configure/deploy/test
```

The intended final result is:

```text
LAB CONFIGURATION READY
```

without requiring separate manual application deployment commands during a normal full rebuild.

---

## Most important validation commands

After a successful `make configure-lab`:

```bash
oc get pods -n banking
oc get svc -n banking
oc get route -n banking

make test-portfolio-java
make test-risk-engine-api
```

Expected application-level success markers:

```text
PORTFOLIO-JAVA END-TO-END VALIDATION: SUCCESS
RISK-ENGINE-API END-TO-END VALIDATION: SUCCESS
```

The Risk Engine test is designed to validate the complete chain:

```text
OpenShift Route
  -> .NET
  -> portfolio-java Service DNS
  -> Java
  -> PostgreSQL
  -> response
```

Useful manual readiness check:

```bash
curl https://risk.apps.okd.lab.talelkarimchebbi.com/health/ready
```

Expected response after the OpenShift deployment has been fully validated:

```text
Healthy
```

---

## Main Make targets

### Full lab

```bash
make configure-lab
```

### OpenStack

```bash
make prepare-openstack
make deploy-openstack
make validate-openstack
make openstack-up
```

### Jenkins

```bash
make configure-jenkins
make configure-jenkins-worker
make test-jenkins-worker
```

### PostgreSQL

```bash
make configure-postgresql
make backup-postgresql
make list-postgresql-backups
make test-postgresql-restore
```

### OpenShift platform

```bash
make configure-openshift-storage
make configure-openshift-registry
make configure-openshift-cicd
make test-openshift-cicd
```

### demo-3tier

```bash
make configure-demo-3tier
make deploy-demo-3tier
make test-demo-3tier
```

### portfolio-java

```bash
make configure-portfolio-java
make helm-template-portfolio-java
make deploy-portfolio-java
make test-portfolio-java
```

### risk-engine-api

```bash
make configure-risk-engine-api
make helm-template-risk-engine-api
make deploy-risk-engine-api
make test-risk-engine-api
```

These individual targets are primarily for troubleshooting. Normal reconstruction should continue to use `make configure-lab`.

---

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
│
├── platform/
│   └── openshift/
│
├── applications/
│   ├── demo-3tier/
│   ├── portfolio-java/
│   ├── risk-engine-api/
│   └── compose.local.yml
│
├── cicd/
│   └── smoke-tests/
│
├── scripts/
├── docs/
└── Makefile
```

---

## Operational documentation

Important runbooks and design documents:

- `docs/runbooks/daily-lab-rebuild.md`
- `docs/runbooks/jenkins-controller.md`
- `docs/runbooks/jenkins-worker.md`
- `docs/runbooks/postgresql-infrastructure.md`
- `docs/runbooks/postgresql-configuration.md`
- `docs/runbooks/postgresql-backup-restore.md`
- `docs/runbooks/edge-gateway.md`
- `docs/runbooks/openstack-workload-access.md`
- OpenShift-specific documentation under `docs/`
- `docs/roadmap.md` for the long-term A-to-Z target

---

## Next validation/documentation milestone

The next session should:

1. rebuild/reconverge the lab from the EC2 foundation with `make configure-lab`;
2. confirm `make test-portfolio-java`;
3. confirm `make test-risk-engine-api`;
4. inspect the final OpenShift resources and network path;
5. produce one global architecture diagram covering AWS, OpenStack, OKD/OpenShift, Jenkins, storage, ingress and the application-to-application/data flows.

That global diagram will become the reference view for explaining the complete platform end to end.
