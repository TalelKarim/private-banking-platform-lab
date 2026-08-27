# OKD runtime Nova machines

This phase creates the first real SCOS machines of the compact OKD cluster:

- temporary bootstrap: `bootstrap` / `10.20.0.11`
- compact control planes: `okd-01` / `10.20.0.21`, `okd-02` / `10.20.0.22`, `okd-03` / `10.20.0.23`

The three permanent machines are both control-plane and schedulable worker nodes. The bootstrap machine exists only while the control plane is being born and is removed in the following installation phase.

## Why this is a separate Terraform layer

The durable OpenStack foundation stays in the HCP Terraform workspace:

```text
HCP Terraform
  -> openshift-net / openshift-subnet
  -> security groups
  -> okd.control flavor
  -> okd-lb
```

The four SCOS machines cannot be created during that foundation run because their first boot requires fresh installer-generated Ignition assets. Their runtime sequence is therefore:

```text
make configure-lab
  -> openshift-install generates bootstrap.ign/master.ign
  -> files are published on okd-lb
  -> runtime Terraform creates the SCOS VMs
```

The runtime Terraform state is kept under `.runtime/openshift/terraform-nodes/`, which is intentionally ignored by Git. Permanent Kolla admin credentials never leave lab-host: the orchestration obtains a short-lived project-scoped Keystone token and exposes only that token to the local runtime Terraform process on ops-runner.

## First-boot handoff

OpenStack Nova receives a small Ignition JSON document through instance `user_data`, with `config_drive = true`. Each stub contains:

1. the node-specific hostname;
2. the HTTP URL of the real installer-generated Ignition document;
3. the SHA-256 hash of that exact document.

Example for `okd-01`:

```text
Nova user_data / config drive
        |
        v
small okd-01 Ignition stub
        |
        | HTTP GET + SHA-256 verification
        v
http://10.20.0.10:8080/master.ign
        |
        v
full installer-generated master configuration
```

The bootstrap stub points to `/bootstrap.ign`; all three control planes point to `/master.ign`.

## Commands

Create or converge the runtime machines:

```bash
make create-okd-nodes
```

Show their Nova status and fixed IPs:

```bash
make status-okd-nodes
```

Inspect first-boot/Ignition output through Nova without needing a floating IP:

```bash
make okd-node-console NODE=bootstrap
make okd-node-console NODE=okd-01
```

Destroy only this runtime layer:

```bash
make destroy-okd-nodes
```

Run that destroy before destroying the HCP-managed OpenStack foundation if the nested OpenStack cloud itself is staying alive long enough for a clean dependency-ordered teardown.

## Expected result of this phase

After `make create-okd-nodes`:

```text
bootstrap  10.20.0.11  ACTIVE  (temporary)
okd-01     10.20.0.21  ACTIVE
okd-02     10.20.0.22  ACTIVE
okd-03     10.20.0.23  ACTIVE
```

`ACTIVE` is a Nova lifecycle state only. It means that the VM is running, not that OKD is already fully installed.

The orchestration additionally waits until Nginx on `okd-lb` has observed HTTP 200 downloads from all four source IPs:

```text
10.20.0.11 -> /bootstrap.ign 200
10.20.0.21 -> /master.ign    200
10.20.0.22 -> /master.ign    200
10.20.0.23 -> /master.ign    200
```

That proves the complete first-boot path:

```text
Nova -> config drive -> Ignition stub -> network -> okd-lb/Nginx -> real Ignition
```

The next phase monitors `openshift-install wait-for bootstrap-complete`, removes the temporary bootstrap machine from HAProxy/runtime infrastructure, then waits for the installation to complete and validates the three nodes with `oc`.
