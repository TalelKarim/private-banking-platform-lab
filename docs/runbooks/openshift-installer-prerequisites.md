# OKD installer prerequisites

## Goal

This layer prepares the reproducible inputs that must exist **before** generating
`install-config.yaml` and Ignition artifacts. It still does not create the
bootstrap or compact control-plane VMs.

```text
ops-runner
  +-- openshift-install  (pinned release)
  +-- oc                 (same release)
  +-- kubectl            (same release)
  |
  +-- asks openshift-install for the matching CoreOS stream metadata
       |
       +-- lab-host downloads the matching OpenStack QCOW2 artifact
            |
            +-- Glance: okd-scos-<release>-x86_64
```

The release is pinned in `platform/openshift/cluster-config.yml`. Do not use a
floating `latest` URL: a daily rebuild must produce the same installer and node
OS until the project deliberately upgrades the pin.

## Why the installer selects the boot image

The script deliberately does not hard-code a CentOS Stream CoreOS image URL.
Instead it runs:

```bash
openshift-install coreos print-stream-json
```

and extracts the OpenStack QCOW2 location + SHA-256 from the pinned installer's
stream metadata. This keeps the VM boot image aligned with the OKD release that
generated the installation assets.

The compressed artifact is downloaded on `lab-host`, its SHA-256 is verified,
it is decompressed, imported to Glance, and the temporary download is removed.
If the Glance image already exists and is active, the import is skipped.

## Commands

Prepare only the tools:

```bash
make prepare-okd-toolchain
```

Prepare only the matching Glance image (also ensures the toolchain first):

```bash
make prepare-okd-image
```

Prepare both:

```bash
make prepare-okd-installation-prereqs
```

`make configure-lab` also runs the combined prerequisite target after the
`okd-lb` Ansible convergence, so the normal daily operator workflow remains:

```text
Terraform AWS apply
  -> Terraform OpenStack apply
     -> make configure-lab
        -> Jenkins / PostgreSQL / Edge
        -> okd-lb DNS + HAProxy + Ignition HTTP
        -> pinned OKD client/installer tooling
        -> matching SCOS image in Glance
```

## Validation

On `ops-runner`:

```bash
openshift-install version
oc version --client
kubectl version --client
```

On `lab-host`:

```bash
export OS_CLIENT_CONFIG_FILE=/data/openstack/secrets/clouds.yaml
/opt/openstack-client-venv/bin/openstack --os-cloud kolla-admin image list
```

Expected image name:

```text
okd-scos-<pinned-release>-x86_64
```

## Daily rebuild behavior

Both operations are idempotent:

- a fresh `ops-runner` downloads the pinned tools once;
- a rebuilt OpenStack cloud imports the matching SCOS image once;
- rerunning `make configure-lab` in the same lab sees both and skips the costly
  work.

Because the current Golden AMI predates the SCOS Glance image, a **full daily
lab destroy/rebuild** currently re-imports the image. After the OpenShift build
is stable, the Golden AMI can be rebaked with the validated image cached in
Glance to make morning rebuilds faster without changing this automation.

## Next phase

The next phase consumes these prerequisites to create fresh runtime installation
assets:

```text
cluster-config.yml
  -> fresh install-config.yaml
  -> openshift-install create manifests
  -> compact-cluster scheduler adjustment
  -> openshift-install create ignition-configs
  -> bootstrap.ign + master.ign
  -> publish runtime Ignition artifacts on okd-lb
```

The installation directory will be regenerated on every full cluster rebuild;
installer-generated certificates and credentials are never committed to Git.
