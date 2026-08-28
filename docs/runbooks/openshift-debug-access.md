# OKD management/debug access guardrails

This step makes the runtime bootstrap repeatable and debuggable from `ops-runner`.

## What is converged

- OpenStack project `admin` compute quotas: 100 instances, 200 cores, 512000 MiB RAM (500 GiB).
- AWS lab-host transit SG: DNS TCP/UDP 53 and OKD API TCP 6443 from the exact ops-runner private IP.
- lab-host Linux forwarding: TCP 22/53/6443 and UDP 53 from the AWS management CIDR to OpenStack floating IPs.
- Neutron `okd-lb` SG: DNS/API from the ops-runner CIDR plus provider-management fallback.
- Neutron `openshift-nodes` SG: explicit SSH from `okd-lb` in addition to the existing machine-network east-west rule.
- ops-runner split-horizon API resolution: `api.okd.lab.test` and `api-int.okd.lab.test` map to the current `okd-lb` floating IP.
- ops-runner SSH aliases: `okd-lb`, `bootstrap`, `okd-01`, `okd-02`, `okd-03`; SCOS nodes are reached through `ProxyJump okd-lb` without copying the private key to the LB.

The API mapping is intentionally an `/etc/hosts` split-horizon override on ops-runner. The private `okd-lb` DNS correctly returns `10.20.0.10` for cluster machines, while ops-runner must use the floating IP because AWS does not route the OpenShift machine CIDR directly.

## Manual targets

```bash
make configure-openstack-runtime
make configure-okd-client-access OKD_LB_FLOATING_IP=192.168.250.x
make ssh-okd-node NODE=okd-01
```

After client access is configured, these also work directly:

```bash
ssh okd-lb
ssh bootstrap
ssh okd-01
ssh okd-02
ssh okd-03
```

Inside a SCOS node, useful bootstrap diagnostics are:

```bash
sudo systemctl --failed
sudo journalctl -b | grep -i ignition
sudo journalctl -u kubelet -b --no-pager | tail -n 200
sudo journalctl -u crio -b --no-pager | tail -n 200
```
