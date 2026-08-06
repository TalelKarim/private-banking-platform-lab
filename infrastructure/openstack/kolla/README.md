# Kolla-Ansible layer

This directory documents the OpenStack deployment layer.

The executable configuration is rendered by the Ansible role
`infrastructure/ansible/roles/kolla_deployer` into `/etc/kolla`.
Secrets are never stored in Git. They are generated once and persisted under
`/data/openstack/secrets`.

Pinned platform versions:

- OpenStack release: `2026.1`
- Kolla-Ansible: `22.0.0`
- Host/container distribution: Ubuntu 24.04
- Neutron mechanism: Open vSwitch
- Cinder backend: dedicated EBS-backed LVM volume group `cinder-volumes`
