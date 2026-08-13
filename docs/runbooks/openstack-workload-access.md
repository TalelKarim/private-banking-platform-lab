# OpenStack workload access from the AWS ops-runner

## Goal

The ops-runner is the permanent Ansible administration plane for workload VMs
inside OpenStack. Workload tenant addresses stay private on `10.10.0.0/24`;
administration crosses the OpenStack provider network through floating IPs.

```text
ops-runner 172.31.x.x
  -> AWS VPC route 192.168.250.0/24 -> lab-host ENI
    -> lab-host Linux forwarding
      -> os-host 192.168.250.1 <-> os-ext veth -> br-ex
        -> workload floating IP 192.168.250.x
          -> Neutron DNAT
            -> workload fixed IP 10.10.0.x:22
```

The route is CIDR-wide, not VM-specific. A future Jenkins, PostgreSQL, OpenShift
node or other VM becomes directly manageable by Ansible as soon as it receives
a floating IP and the shared `lab-management` security group. No new AWS route
or lab-host forwarding rule is required per VM.

## One-time private-key bootstrap

The matching public key is provided to Terraform OpenStack through the HCP
workspace variable `workload_ssh_public_key`. Store the private half once in SSM
Parameter Store outside Terraform so it never enters Terraform state.

From the Mac, after creating the dedicated key:

```bash
aws ssm put-parameter \
  --region eu-south-2 \
  --name /private-banking-platform-lab/openstack/workload-ssh-private-key \
  --type SecureString \
  --value "file://$HOME/.ssh/private-banking-openstack-workloads" \
  --overwrite
```

The AWS Terraform layer grants only `ssm:GetParameter` for this exact parameter
to the ops-runner role. Cloud-init retrieves it with decryption and writes:

```text
/home/ubuntu/.ssh/private-banking-openstack-workloads
mode 0600, owner ubuntu
```

Changing the ops-runner user-data intentionally replaces that stateless EC2.
The HCP Terraform agent reconnects from the replacement instance.

## Apply order

1. Put the workload private key in the SSM SecureString shown above.
2. Apply the AWS Terraform plan. Expected infrastructure changes are the VPC
   route, the narrow SSM read policy, and an ops-runner replacement caused by
   its updated bootstrap. The OpenStack lab-host must not be replaced.
3. On the lab-host repository checkout, pull this revision and rerun the host
   Ansible role with `make bootstrap-ansible`. This updates the persistent
   external-network systemd script with the inbound SSH forwarding rule.
4. Apply the OpenStack Terraform plan. The generic `lab-management` security
   group gains SSH ingress from `172.31.16.0/20`; existing workloads using that
   security group inherit the rule automatically.

## Validation

On the ops-runner:

```bash
ip route get 192.168.250.100
ls -l /home/ubuntu/.ssh/private-banking-openstack-workloads
```

The Linux route can still show the normal AWS default gateway; the important
route to `192.168.250.0/24` lives in the AWS VPC route table, not as a special
Linux route on the runner.

After Jenkins has a floating IP:

```bash
JENKINS_FIP=<floating-ip>
ssh -i /home/ubuntu/.ssh/private-banking-openstack-workloads \
  ubuntu@"$JENKINS_FIP"
```

On the lab-host, verify the permanent forwarding rule:

```bash
sudo iptables -C FORWARD \
  -i enp39s0 -o os-host \
  -s 172.31.16.0/20 -d 192.168.250.0/24 \
  -p tcp --dport 22 \
  -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
```

This management path is deliberately limited to SSH. Application ports are
opened separately only when a platform service actually needs them.
