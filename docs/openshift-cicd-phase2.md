# OpenShift CI/CD Phase 2 - Jenkins integration

## Goal

Phase 2 turns the existing Jenkins worker into the external CI/CD execution plane for OKD.
The integration is platform-level and is reused by `demo-3tier`, Java, .NET and future workloads.

```text
Jenkins controller
       |
       v
Jenkins worker (10.10.0.30)
       |
       +-- HTTPS/6443 --> okd-lb 10.20.0.10 --> kube-apiserver
       |
       +-- HTTPS/443  --> okd-lb 10.20.0.10 --> OpenShift router
                                               |
                                               v
                                      integrated image registry
                                               |
                                               v
                                          Cinder PVC
```

The registry Route uses the normal OpenShift apps hostname but is private in practice:

- Jenkins resolves the registry hostname directly to `10.20.0.10` using split-horizon `/etc/hosts`.
- The AWS public edge has an exact Nginx virtual host for the registry name that returns HTTP 404.
- The existing wildcard `*.apps.okd...` continues to expose normal OpenShift application Routes.

## Identity and RBAC

OpenShift objects:

- namespace `cicd`
- ServiceAccount `cicd/jenkins`
- long-lived lab token Secret `cicd/jenkins-api-token`
- ClusterRole `private-banking-jenkins-deployer`
- RoleBinding in `demo` for deployment rights
- RoleBinding in `demo` to OpenShift `system:image-builder` for registry pushes

The ServiceAccount has no cluster-admin binding and is explicitly checked to have no `get nodes` access.
The static token is a lab trade-off for an external persistent Jenkins. It is regenerated with the cluster and
re-injected into Jenkins by `make configure-lab`; it is never stored in Git.

## Jenkins worker

Ansible installs and configures:

- cluster-matched `oc`
- Podman, Buildah and Skopeo
- rootless container user namespace ranges for the `jenkins` user
- API and ingress CA trust
- private hostname mappings for the API and registry

## Jenkins controller

Ansible creates or updates:

- secret-text credential `openshift-ci-token`
- managed pipeline job `platform-openshift-smoke`

The token exists on disk only in runtime-only files while Ansible updates Jenkins and those files are deleted afterwards.

## End-to-end smoke

`make test-openshift-cicd` triggers Jenkins and proves the complete path:

```text
Jenkins worker
  -> authenticate as system:serviceaccount:cicd:jenkins
  -> build a small UBI image with rootless Podman
  -> push it to the integrated OpenShift registry
  -> read the resulting ImageStreamTag
  -> deploy its immutable image reference in namespace demo
  -> wait for Deployment rollout success
```

A successful smoke leaves `demo/phase2-smoke` running and an ImageStream named `phase2-smoke` as evidence.

## Daily rebuild behavior

`make configure-lab` performs Phase 2 after the OKD/Cinder/registry Phase 1 foundation is healthy.
A new cluster creates a new ServiceAccount token and the Jenkins credential is updated automatically.
No manual OpenShift console or Jenkins UI step is required.
