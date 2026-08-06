SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap-ansible prepare-openstack prechecks-openstack deploy-openstack openstack-up openstack-status validate-openstack reconfigure-openstack stop-openstack

help:
	@printf '%s\n' \
	  'bootstrap-ansible     Install the local Ansible control environment and configure the host' \
	  'prepare-openstack     Configure the host, run Kolla bootstrap-servers and prechecks' \
	  'deploy-openstack      Pull images, deploy OpenStack and generate admin credentials' \
	  'openstack-up          Run the complete prepare + deploy + validate chain' \
	  'openstack-status      Show the running Kolla containers' \
	  'validate-openstack    Query the OpenStack control plane with the admin cloud' \
	  'reconfigure-openstack Apply Kolla configuration changes' \
	  'stop-openstack        Stop the OpenStack containers'

bootstrap-ansible:
	./scripts/bootstrap-ansible.sh

prepare-openstack: bootstrap-ansible
	./scripts/kolla.sh prepare

prechecks-openstack:
	./scripts/kolla.sh prechecks

deploy-openstack:
	./scripts/kolla.sh deploy

openstack-up:
	./scripts/openstack-up.sh

openstack-status:
	./scripts/kolla.sh status

validate-openstack:
	./scripts/kolla.sh validate

reconfigure-openstack:
	./scripts/kolla.sh reconfigure

stop-openstack:
	./scripts/kolla.sh stop
