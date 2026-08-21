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

## Current implemented phase

The infrastructure foundation and the first platform service are now validated end to end.

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
- `make configure-lab`, executed from `ops-runner`, is now the single convergence entry point for the configuration layer. It discovers the current Jenkins Floating IP and converges Jenkins and the edge gateway automatically.

## Daily rebuild workflow

The normal lab rebuild is intentionally reduced to three operator actions:

```text
1. Terraform AWS apply
   -> lab-host + ops-runner + edge-gateway

2. Terraform OpenStack apply
   -> networks + router + Jenkins VM/volume/Floating IP

3. On ops-runner:
   make configure-lab
   -> Jenkins + Nginx convergence
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
make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x
```

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
│   ├── portfolio-java/
│   └── risk-engine-dotnet/
├── scripts/
├── docs/
└── Makefile
```

## Current next step

Build the **Jenkins execution plane** instead of running builds on the controller:

1. create a dedicated Jenkins build-agent VM in OpenStack with Terraform;
2. configure it with Ansible (Java 21, Maven, Git and Jenkins agent prerequisites);
3. connect it to the controller over the private OpenStack network;
4. run the first real Java pipeline on the agent (`checkout -> mvn clean verify -> package -> archive artifact`);
5. validate that no build workload runs on the Jenkins controller.

After that, the lab moves to the application/data platform: PostgreSQL, the Spring Boot and .NET workloads, then OpenShift and observability.

See `docs/roadmap.md` for the complete phase plan.

## Workload runbooks

- Daily rebuild: `docs/runbooks/daily-lab-rebuild.md`
- Jenkins controller: `docs/runbooks/jenkins-controller.md`
- Edge gateway: `docs/runbooks/edge-gateway.md`
- OpenStack workload access: `docs/runbooks/openstack-workload-access.md`
