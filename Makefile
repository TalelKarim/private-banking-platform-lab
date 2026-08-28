SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap-ansible configure-lab configure-openstack-runtime configure-okd-client-access configure-jenkins configure-jenkins-worker test-jenkins-worker configure-postgresql backup-postgresql list-postgresql-backups test-postgresql-restore restore-postgresql configure-edge-gateway configure-okd-lb prepare-okd-toolchain prepare-okd-image prepare-okd-installation-prereqs generate-okd-install-assets publish-okd-ignition prepare-okd-install-assets create-okd-nodes complete-okd-installation status-okd-nodes destroy-okd-nodes okd-node-console ssh-okd-node prepare-openstack prechecks-openstack deploy-openstack openstack-up openstack-status validate-openstack reconfigure-openstack stop-openstack prepare-golden-ami bake-golden-ami activate-golden-ami deactivate-golden-ami

help:
	@printf '%s\n' \
	  'bootstrap-ansible     Install the local Ansible control environment and configure the host' \
	  'configure-lab         Discover runtime addresses and converge all lab services from ops-runner' \
	  'configure-openstack-runtime Converge OpenStack quotas + routed management forwarding' \
	  'configure-okd-client-access Configure ops-runner API resolution + SSH jump aliases' \
	  'configure-jenkins    Configure and validate the Jenkins controller from the ops-runner' \
	  'configure-jenkins-worker Configure/register the dedicated Jenkins build worker' \
	  'test-jenkins-worker Run the Java/.NET smoke pipeline on the dedicated Jenkins worker' \
	  'configure-postgresql Configure PostgreSQL, Cinder data, roles, database and backup timer' \
	  'backup-postgresql    Create an on-demand PostgreSQL logical dump' \
	  'list-postgresql-backups List retained PostgreSQL dump archives' \
	  'test-postgresql-restore Restore a fresh dump into a temporary DB and validate it' \
	  'restore-postgresql   Restore BACKUP into TARGET_DB; live DB requires explicit CONFIRM' \
	  'configure-edge-gateway Configure Nginx ingress on the edge gateway from the ops-runner' \
	  'configure-okd-lb      Configure OKD DNS, HAProxy and Ignition HTTP on okd-lb' \
	  'prepare-okd-toolchain Install the pinned openshift-install, oc and kubectl on ops-runner' \
	  'prepare-okd-image     Import the installer-matched SCOS OpenStack image into Glance' \
	  'prepare-okd-installation-prereqs Prepare OKD tools + matching Glance boot image' \
	  'generate-okd-install-assets Generate fresh manifests, Ignition and auth assets' \
	  'publish-okd-ignition Publish runtime bootstrap/master Ignition on okd-lb' \
	  'prepare-okd-install-assets Generate + publish fresh runtime OKD install assets' \
	  'create-okd-nodes      Create/converge bootstrap + 3 compact SCOS control-plane VMs' \
	  'complete-okd-installation Wait bootstrap-complete, retire bootstrap, then wait install-complete' \
	  'status-okd-nodes      Show Nova status/fixed IPs for OKD runtime machines' \
	  'destroy-okd-nodes     Destroy only bootstrap + compact control-plane VMs' \
	  'okd-node-console      Show Nova console: make okd-node-console NODE=okd-01' \
	  'ssh-okd-node          SSH through okd-lb: make ssh-okd-node NODE=okd-01' \
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

configure-jenkins-worker:
	@test -n "$(JENKINS_FLOATING_IP)" || (echo "Usage: make configure-jenkins-worker JENKINS_FLOATING_IP=192.168.250.x JENKINS_WORKER_FLOATING_IP=192.168.250.y" >&2; exit 2)
	@test -n "$(JENKINS_WORKER_FLOATING_IP)" || (echo "Usage: make configure-jenkins-worker JENKINS_FLOATING_IP=192.168.250.x JENKINS_WORKER_FLOATING_IP=192.168.250.y" >&2; exit 2)
	./scripts/configure-jenkins-worker.sh "$(JENKINS_FLOATING_IP)" "$(JENKINS_WORKER_FLOATING_IP)"

test-jenkins-worker:
	./scripts/test-jenkins-worker.sh "$(JENKINS_FLOATING_IP)"

configure-postgresql:
	@test -n "$(POSTGRESQL_FLOATING_IP)" || (echo "Usage: make configure-postgresql POSTGRESQL_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/configure-postgresql.sh "$(POSTGRESQL_FLOATING_IP)"

backup-postgresql:
	POSTGRESQL_FLOATING_IP="$(POSTGRESQL_FLOATING_IP)" ./scripts/postgresql-backup.sh backup

list-postgresql-backups:
	POSTGRESQL_FLOATING_IP="$(POSTGRESQL_FLOATING_IP)" ./scripts/postgresql-backup.sh list

test-postgresql-restore:
	POSTGRESQL_FLOATING_IP="$(POSTGRESQL_FLOATING_IP)" BACKUP="$(BACKUP)" ./scripts/postgresql-backup.sh test-restore

restore-postgresql:
	POSTGRESQL_FLOATING_IP="$(POSTGRESQL_FLOATING_IP)" BACKUP="$(BACKUP)" TARGET_DB="$(TARGET_DB)" CONFIRM="$(CONFIRM)" ./scripts/postgresql-backup.sh restore

configure-edge-gateway:
	@test -n "$(JENKINS_FLOATING_IP)" || (echo "Usage: make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x OKD_LB_FLOATING_IP=192.168.250.y" >&2; exit 2)
	@test -n "$(OKD_LB_FLOATING_IP)" || (echo "Usage: make configure-edge-gateway JENKINS_FLOATING_IP=192.168.250.x OKD_LB_FLOATING_IP=192.168.250.y" >&2; exit 2)
	./scripts/configure-edge-gateway.sh "$(JENKINS_FLOATING_IP)" "$(OKD_LB_FLOATING_IP)"


configure-openstack-runtime:
	./scripts/configure-openstack-runtime.sh

configure-okd-client-access:
	@test -n "$(OKD_LB_FLOATING_IP)" || (echo "Usage: make configure-okd-client-access OKD_LB_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/configure-okd-client-access.sh "$(OKD_LB_FLOATING_IP)"

configure-okd-lb:
	@test -n "$(OKD_LB_FLOATING_IP)" || (echo "Usage: make configure-okd-lb OKD_LB_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/configure-okd-lb.sh "$(OKD_LB_FLOATING_IP)"

prepare-okd-toolchain:
	./scripts/prepare-okd-toolchain.sh

prepare-okd-image: prepare-okd-toolchain
	./scripts/prepare-okd-image.sh

prepare-okd-installation-prereqs:
	./scripts/prepare-okd-installation-prereqs.sh

generate-okd-install-assets: prepare-okd-toolchain
	./scripts/generate-okd-install-assets.sh

publish-okd-ignition:
	@test -n "$(OKD_LB_FLOATING_IP)" || (echo "Usage: make publish-okd-ignition OKD_LB_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/publish-okd-ignition.sh "$(OKD_LB_FLOATING_IP)"

prepare-okd-install-assets: prepare-okd-installation-prereqs
	@test -n "$(OKD_LB_FLOATING_IP)" || (echo "Usage: make prepare-okd-install-assets OKD_LB_FLOATING_IP=192.168.250.x" >&2; exit 2)
	./scripts/prepare-okd-install-assets.sh "$(OKD_LB_FLOATING_IP)"

create-okd-nodes:
	./scripts/okd-nodes.sh apply

complete-okd-installation:
	./scripts/complete-okd-installation.sh "$(OKD_LB_FLOATING_IP)"

status-okd-nodes:
	./scripts/okd-nodes.sh status

destroy-okd-nodes:
	./scripts/okd-nodes.sh destroy

okd-node-console:
	@test -n "$(NODE)" || (echo "Usage: make okd-node-console NODE=bootstrap|okd-01|okd-02|okd-03" >&2; exit 2)
	./scripts/okd-nodes.sh console "$(NODE)"

ssh-okd-node:
	@test -n "$(NODE)" || (echo "Usage: make ssh-okd-node NODE=bootstrap|okd-01|okd-02|okd-03" >&2; exit 2)
	./scripts/ssh-okd-node.sh "$(NODE)"

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
