# OpenShift storage + integrated registry foundation (phase 1)

## Purpose

This phase makes persistent storage a reproducible platform capability before Jenkins starts pushing application images.

The OKD cluster is intentionally installed with `platform: none`. Therefore the OpenShift installer does not know that the machines themselves are Nova instances and does not automatically install the OpenStack Cinder CSI integration.

The converged storage path is:

```text
PVC
  -> StorageClass cinder-standard
  -> cinder.csi.openstack.org
  -> Keystone / Nova / Cinder APIs
  -> Cinder block volume
  -> PV
  -> OKD node / Pod
```

The integrated image registry then uses the same platform service:

```text
openshift-image-registry/image-registry
  -> PVC image-registry-storage
  -> StorageClass cinder-standard
  -> Cinder CSI
  -> OpenStack Cinder
```

## What is committed vs generated at runtime

Committed to Git:

- pinned Helm and Cinder CSI chart versions;
- Cinder CSI Helm values;
- OpenShift SCC/RBAC needed by the node plugin;
- the default `cinder-standard` StorageClass;
- the registry PVC definition;
- the registry convergence script;
- the destroy-time storage cleanup guard;
- the Nova compute recovery override.

Generated at runtime and never committed:

- the dedicated OpenStack `okd-cinder-csi` password;
- the Cinder CSI `cloud.conf` Secret;
- PV names and Cinder volume UUIDs;
- OKD installer auth assets.

The Cinder CSI password is persisted as an AWS SSM SecureString so repeated `make configure-lab` executions reconcile the same technical user instead of creating credentials in Git or Terraform state.

## Registry design for this lab

Cinder is block storage and the PVC is `ReadWriteOnce`. For this compact disposable lab the registry is deliberately configured as:

```text
replicas: 1
rolloutStrategy: Recreate
PVC: image-registry-storage
size: 20Gi
```

This is a lab trade-off, not the target design for a production multi-replica registry. The external registry Route remains disabled in phase 1. Phase 2 creates the Jenkins-only access path, DNS/TLS trust, ServiceAccount/RBAC and push/deploy smoke test without unintentionally publishing the registry through the public AWS edge.

## Daily convergence

After the normal AWS Terraform and OpenStack Terraform applies, the operator still runs one command from `ops-runner`:

```bash
make configure-lab
```

The command now also:

```text
recover known Nova guests after a lab-host reboot/Spot stop
  -> install persistent Nova guest auto-resume configuration
  -> install pinned Helm
  -> complete OKD installation
  -> create/reconcile the Cinder CSI OpenStack service user
  -> install/reconcile Cinder CSI
  -> create/reconcile cinder-standard
  -> run a real 1Gi PVC + Pod write smoke test
  -> create/reconcile registry PVC
  -> configure the integrated registry on that PVC
  -> validate CSI, StorageClass, PVC and image-registry ClusterOperator
```

Every operation is intended to be idempotent. A second `make configure-lab` converges existing resources rather than requiring manual cleanup. A successful CSI smoke test also writes `.runtime/openshift/storage-foundation.ready`; the destroy path uses that runtime marker to fail closed if the Kubernetes API is unavailable while Cinder-backed volumes may still exist.

## Destroy safety

`make destroy-okd-nodes` invokes `scripts/cleanup-openshift-storage.sh` before Terraform destroys the OKD VMs.

The cleanup order is important:

```text
stop/remove integrated registry
  -> delete registry PVC
  -> wait for Cinder-backed PV deletion
  -> uninstall Cinder CSI
  -> delete StorageClass / CSI Secret / SCC binding
  -> only then destroy OKD VMs
```

If another Cinder-backed PV still exists, the cleanup refuses to continue. That is intentional: it prevents Terraform from destroying the nodes while a volume is still attached and creating an orphaned/blocked Cinder lifecycle. Future application phases must add their PVC cleanup to the same controlled teardown path.

If the cluster is genuinely unrecoverable, `SKIP_OPENSHIFT_STORAGE_CLEANUP=true make destroy-okd-nodes` exists only as an emergency escape hatch. It can orphan Cinder volumes and must not be part of the normal daily workflow.

## Verification

After `make configure-lab`:

```bash
export KUBECONFIG="$PWD/.runtime/openshift/install/auth/kubeconfig"

oc get csidriver
oc get storageclass
oc get pvc -n openshift-image-registry
oc get clusteroperator image-registry
oc get config.imageregistry.operator.openshift.io/cluster -o yaml
```

Expected essentials:

```text
CSIDriver:      cinder.csi.openstack.org
StorageClass:   cinder-standard (default)
Registry PVC:   image-registry-storage   Bound
Registry CO:    Available=True
Registry route: disabled during phase 1
```

On `lab-host`, the corresponding dynamically provisioned block volume can also be inspected with the existing Kolla admin OpenStack client.
