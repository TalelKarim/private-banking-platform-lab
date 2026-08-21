SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap-ansible configure-lab configure-jenkins configure-edge-gateway prepare-openstack prechecks-openstack deploy-openstack openstack-up openstack-status validate-openstack reconfigure-openstack stop-openstack prepare-golden-ami bake-golden-ami activate-golden-ami deactivate-golden-ami

help:
	@printf '%s\n' \
	  'bootstrap-ansible     Install the local Ansible control environment and configure the host' \
	  'configure-lab         Discover runtime addresses and converge all lab services from ops-runner' \
	  'configure-jenkins    Configure and validate the Jenkins controller from the ops-runner' \
	  'configure-edge-gateway Configure Nginx ingress on the edge gateway from the ops-runner' \
	  'prepare-openstack     Configure the host, run Kolla bootstrap-servers and prechecks' \
	  'deploy-openstack      Pull images, deploy OpenStack and generate admin credentials' \
	  'openstack-up          Run the complete prepare + deploy + validate chain' \
	  'openstack-status      Show the running Kolla containers' \
	  'validate-openstack    Query the OpenStack control plane with the admin cloud' \
	  'reconfigure-openstack Apply Kolla configuration changes' \
	  'stop-openstack        Stop the OpenStack containers' \
	  'prepare-golden-ami   Clean test workloads and prepare the current EC2 for baking' \
	  'bake-golden-ami      Stop the source EC2 and create a 3-volume Golden AMI from the Mac' \
	  'activate-golden-ami  Write local Terraform Golden mode (AMI_ID=ami-...)' \
	  'deactivate-golden-ami Return Terraform to stock-Ubuntu bootstrap mode'

bootstrap-ansible:
	./scripts/bootstrap-ansible.sh

configure-lab:
	./scripts/configure-lab.sh

configure-jenkins:
	@test -n "$(JENKINS_FLOATING_IP)" || (echo "Usage: make configure-jenkins JENKINS_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/configure-jenkins.sh "$(JENKINS_FLOATING_IP)"

configure-edge-gateway:
	@test -n "$(JENKINS_FLOATING_IP)" || (echo "Usage: make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/configure-edge-gateway.sh "$(JENKINS_FLOATING_IP)"

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

prepare-golden-ami:
	./scripts/prepare-golden-ami.sh

bake-golden-ami:
	./scripts/bake-golden-ami.sh

activate-golden-ami:
	@test -n "$(AMI_ID)" || (echo "Usage: make activate-golden-ami AMI_ID=ami-..." >&2; exit 2)
	./scripts/activate-golden-ami.sh "$(AMI_ID)"

deactivate-golden-ami:
	./scripts/deactivate-golden-ami.sh
