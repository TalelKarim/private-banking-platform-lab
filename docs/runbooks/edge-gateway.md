# Edge gateway runbook

The edge gateway is the single AWS-side HTTP/HTTPS ingress point for web tools and applications hosted by nested OpenStack.

Current path:

```text
Browser -> Edge EIP:80 -> Nginx -> Jenkins FIP:8080 -> VPC route -> lab-host FORWARD -> Neutron -> Jenkins
```

Ownership:
- Terraform: edge EC2, EIP, IAM, AWS SGs and transit permissions.
- cloud-init: hostname, Python, SSH and SSM only.
- Ansible: Nginx and evolving reverse-proxy routes.
- OpenStack Terraform: workload SG rules.

Configure from ops-runner:

```bash
make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x
```

Before Route53/TLS, use Terraform output `edge_gateway_http_url`. Jenkins is the default HTTP virtual host. Later replace `_` with the real Jenkins DNS name and add Grafana/OpenShift entries to `edge_nginx_routes`.

PostgreSQL stays private and is never published through this edge.
