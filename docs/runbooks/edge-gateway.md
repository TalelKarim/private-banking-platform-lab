# Edge gateway runbook

The edge gateway is the AWS-side reverse-proxy layer between the public ALB and services hosted by the nested OpenStack lab. It is not the OKD load balancer.

## Current ingress architecture

```text
Browser / CLI
    |
Route53
    |
AWS ALB + ACM
(TLS termination)
    |
edge-gateway Nginx
172.31.31.71
    |
    +--> jenkins.lab.talelkarimchebbi.com
    |      -> Jenkins Floating IP :8080
    |
    +--> cloud.lab.talelkarimchebbi.com
    |      -> lab-host / Horizon :80
    |
    +--> *.apps.okd.lab.talelkarimchebbi.com
           -> okd-lb Floating IP :443
                -> HAProxy
                -> OpenShift Ingress Router
                -> Route -> Service -> Pods
```

The OKD API uses the same internal load-balancer VM from the administration path:

```text
ops-runner / oc
    -> api.okd.lab.talelkarimchebbi.com:6443
    -> okd-lb
    -> HAProxy :6443
    -> okd-01 / okd-02 / okd-03 API servers
```

### edge-gateway vs okd-lb

- **edge-gateway** is the public/application reverse proxy for the whole lab. It routes by HTTP Host name after the AWS ALB/ACM entry path.
- **okd-lb** is an OpenStack VM dedicated to the OKD cluster. HAProxy load-balances the Kubernetes API (:6443), Machine Config Server (:22623) and OpenShift ingress (:80/:443) across the compact control-plane nodes.
- Public OpenShift application traffic therefore crosses both layers: ALB -> edge-gateway -> okd-lb -> OpenShift Ingress Router.
- Jenkins and Horizon do not pass through the OKD load balancer.

## Ownership

- Terraform AWS: ALB, ACM integration, Route53 aliases, edge EC2, IAM, AWS SGs and routing.
- cloud-init: minimal edge host bootstrap.
- Ansible: Nginx configuration and host-based reverse-proxy routes.
- Terraform/OpenStack + Ansible: workload Floating IPs, security groups and `okd-lb` HAProxy/DNS configuration.

## Configure from ops-runner

Normally `make configure-lab` discovers current Floating IPs and invokes the edge configuration automatically.

For troubleshooting:

```bash
make configure-edge-gateway \
  JENKINS_FLOATING_IP=192.168.250.x \
  OKD_LB_FLOATING_IP=192.168.250.y
```

Current public names:

```text
https://jenkins.lab.talelkarimchebbi.com
https://cloud.lab.talelkarimchebbi.com
https://console-openshift-console.apps.okd.lab.talelkarimchebbi.com
https://portfolio.apps.okd.lab.talelkarimchebbi.com
https://risk.apps.okd.lab.talelkarimchebbi.com
```

The OpenShift integrated-registry route is intentionally private-only at the edge. PostgreSQL also remains private and is never published through this gateway.
