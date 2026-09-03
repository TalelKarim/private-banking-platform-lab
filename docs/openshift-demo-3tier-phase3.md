# Phase 3 - demo-3tier application on OpenShift

Phase 3 turns the platform built in Phases 1 and 2 into a real application path. It intentionally uses raw Kubernetes/OpenShift YAML instead of Helm so each primitive remains visible while learning.

## Responsibility split

```text
Terraform AWS/OpenStack
  owns machines, networks, ALB, Route53 and block-storage infrastructure

Ansible/platform scripts on ops-runner
  ensure the generated DB Secret and managed Jenkins job

Jenkins controller
  stores the OpenShift credential and the demo job definition

Jenkins worker
  clones Git, builds frontend/backend images, pushes them and runs oc

OpenShift
  owns Deployment / StatefulSet / Service / Route / ConfigMap / Secret / PVC

OpenStack Cinder
  owns the physical block volume backing PostgreSQL
```

## Jenkins flow

```text
public GitHub repository
        |
        v
Jenkins worker checkout
        |
        +-- OpenShift token -> oc login -> temporary kubeconfig
        |
        +-- Podman build demo-frontend + demo-backend
        |
        +-- Podman push -> OpenShift integrated registry
        |
        +-- ImageStreamTag -> immutable @sha256 image reference
        |
        +-- oc apply raw manifests
        v
OpenShift controllers
        -> StatefulSet/PostgreSQL/PVC
        -> backend Deployment/Service
        -> frontend Deployment/Service
        -> public Route
```

The image tag is the short Git commit SHA. Deployments are not left on a mutable tag: Jenkins resolves each ImageStreamTag to its immutable digest and writes that digest into the Deployment.

## Application request flow

```text
browser
  -> Route53 wildcard
  -> AWS ALB + ACM certificate
  -> edge-gateway Nginx
  -> okd-lb
  -> OpenShift ingress router
  -> Route demo-3tier
  -> frontend Service
  -> frontend Pod / Nginx
  -> backend Service
  -> backend Pod
  -> demo-postgres Service
  -> PostgreSQL StatefulSet Pod
  -> PVC
  -> Cinder CSI
  -> OpenStack Cinder
```

Only the frontend has an OpenShift Route. The backend and PostgreSQL are reachable through cluster Services only. Browser calls to `/api/*` first reach frontend Nginx; Nginx resolves `demo-backend` through Kubernetes DNS and reverse-proxies the request internally.

## Persistence model

The PostgreSQL StatefulSet creates the deterministic PVC:

```text
postgres-data-demo-postgres-0
```

Its StorageClass is `cinder-standard`, so dynamic provisioning creates a real Cinder volume. Replacing the PostgreSQL Pod keeps the StatefulSet identity and reuses the same PVC. `make destroy-okd-nodes` uses the Phase 1 cleanup to delete every Cinder-backed PVC before destroying the OKD VMs, preventing orphaned lab volumes.

## Secret model

The manifests contain no database password. `make configure-demo-3tier` creates `demo/demo-postgres-credentials` only when absent, using a random password. Reruns reuse the Secret so an existing PostgreSQL PVC does not silently receive a different password.

## Public ingress scope

The hostname is:

```text
https://demo.apps.okd.lab.talelkarimchebbi.com
```

It reuses the pre-existing Route53 wildcard, ACM certificate, public ALB and edge-gateway wildcard. The ALB itself is Internet-facing, but its Security Group still restricts clients to the configured lab CIDR and optional cloud-browser EIP. Phase 3 does not weaken that boundary.

## Validation

```bash
make test-demo-3tier
```

proves:

- StatefulSet, backend and frontend rollout success;
- PostgreSQL PVC is `Bound` and exposes a Cinder CSI volume handle;
- frontend/backend Deployments use immutable `@sha256` image references;
- a request through the frontend Service crosses Nginx -> backend Service -> PostgreSQL and returns seeded positions;
- the OpenShift Route works through okd-lb using the real OpenShift ingress CA;
- application Pods, Services, Route, ImageStreams and PVC are visible for inspection.
