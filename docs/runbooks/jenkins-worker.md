# Jenkins worker provisioning and validation runbook

## Goal

Provide one dedicated OpenStack build worker so the Jenkins controller remains an orchestration service rather than a build machine.

## Architecture

```text
ops-runner
   │
   │ SSH through worker Floating IP (Ansible only)
   ▼
jenkins-agent-01
10.10.0.30
   │
   │ outbound Jenkins Remoting over WebSocket / HTTP 8080
   ▼
jenkins-controller
10.10.0.20
```

The worker Floating IP is only an administration path for the ops-runner. The Jenkins agent channel uses `private-net` directly and does not traverse the edge gateway.

## Worker baseline

Terraform creates `jenkins-agent-01` with:

- `lab.medium` (2 vCPU, 4 GiB RAM, 20 GiB root);
- fixed IP `10.10.0.30`;
- `lab-management` plus `jenkins-worker` Security Groups;
- one Floating IP for Ansible administration;
- no Cinder data volume because build workspaces and dependency caches are disposable in this daily-rebuilt lab.

Ansible installs/configures:

- OpenJDK 21 JDK;
- Maven;
- Git through the common Linux baseline;
- .NET 8 SDK;
- dedicated `jenkins` system user;
- Maven and NuGet cache directories under `/var/lib/jenkins-agent`;
- controller-matched `agent.jar`;
- a systemd-managed inbound Jenkins agent.

The inbound secret is retrieved from Jenkins by Ansible, kept out of Git, written root/`jenkins` readable on the worker, and passed to `agent.jar` through `-secret @file` rather than as clear text in the process arguments.

## Daily convergence

From the ops-runner repository checkout:

```bash
make configure-lab
```

The orchestrator discovers both runtime Floating IPs, configures the controller, registers/reconciles the worker node and smoke job, configures the worker, waits for it to be online, and finally converges the edge gateway.

For worker-only troubleshooting:

```bash
make configure-jenkins-worker \
  JENKINS_FLOATING_IP=192.168.250.x \
  JENKINS_WORKER_FLOATING_IP=192.168.250.y
```

## Smoke pipeline

The infrastructure smoke job is named:

```text
platform-worker-smoke
```

Run it from the Jenkins UI or from the ops-runner:

```bash
make test-jenkins-worker
```

The target automatically discovers the controller Floating IP when it is not supplied, triggers the job, waits for completion, requires `SUCCESS`, and verifies that Jenkins archived a Java `.jar`.

The pipeline also asserts:

```text
NODE_NAME == jenkins-agent-01
```

so a successful smoke build proves that the build did not run on the controller.

## Useful validation commands on the worker

```bash
hostname
java -version
javac -version
mvn -version
dotnet --version
systemctl is-active jenkins-agent
sudo journalctl -u jenkins-agent --no-pager -n 100
```

Expected hostname:

```text
jenkins-agent-01
```
