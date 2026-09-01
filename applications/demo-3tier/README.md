# demo-3tier

Learning workload that will be the first consumer of the reusable Jenkins -> OpenShift CI/CD foundation.

Planned application shape:

```text
OpenShift Route
  -> frontend Service -> frontend Deployment/Pods
  -> backend Service  -> backend Deployment/Pods
  -> postgres Service -> postgres StatefulSet -> PVC
```

Phase 1 intentionally contains no application implementation yet. It first establishes Cinder CSI and persistent storage for the OpenShift integrated registry. Phase 2 wires Jenkins authentication, private registry access and deployment permissions; the frontend/backend code and manifests then consume that platform foundation.
