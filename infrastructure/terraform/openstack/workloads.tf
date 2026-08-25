module "jenkins_controller" {
  source = "./modules/compute-instance"

  # A floating IP can only be associated once Neutron has a complete path
  # from the private subnet to the external network through the router.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.jenkins_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.jenkins_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.jenkins.id,
  ]

  create_floating_ip  = true
  external_network    = openstack_networking_network_v2.external.name
  external_subnet_id  = openstack_networking_subnet_v2.external.id
  data_volume_size_gb = var.jenkins_data_volume_size_gb

  metadata = {
    environment = "lab"
    role        = "jenkins-controller"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "jenkins",
    "platform",
  ]
}

module "jenkins_worker" {
  source = "./modules/compute-instance"

  # The worker receives a Floating IP only for ops-runner/Ansible management.
  # Jenkins Remoting itself uses the private OpenStack network.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.jenkins_worker_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.jenkins_worker_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.jenkins_worker.id,
  ]

  create_floating_ip = true
  external_network   = openstack_networking_network_v2.external.name
  external_subnet_id = openstack_networking_subnet_v2.external.id

  metadata = {
    environment = "lab"
    role        = "jenkins-worker"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "jenkins",
    "worker",
    "platform",
  ]
}

module "postgresql" {
  source = "./modules/compute-instance"

  # The floating IP is management-only: ops-runner/Ansible reaches SSH through
  # the provider network. PostgreSQL/5432 itself stays private to 10.10.0.0/24.
  depends_on = [openstack_networking_router_interface_v2.private]

  name       = var.postgresql_instance_name
  image_id   = openstack_images_image_v2.ubuntu_2404.id
  flavor_id  = openstack_compute_flavor_v2.medium.id
  key_pair   = openstack_compute_keypair_v2.workload.name
  network_id = openstack_networking_network_v2.private.id
  subnet_id  = openstack_networking_subnet_v2.private.id
  fixed_ip   = var.postgresql_fixed_ip

  security_group_ids = [
    openstack_networking_secgroup_v2.management.id,
    openstack_networking_secgroup_v2.postgresql.id,
  ]

  create_floating_ip  = true
  external_network    = openstack_networking_network_v2.external.name
  external_subnet_id  = openstack_networking_subnet_v2.external.id
  data_volume_size_gb = var.postgresql_data_volume_size_gb

  metadata = {
    environment = "lab"
    role        = "postgresql"
    managed_by  = "terraform"
  }

  tags = [
    "lab",
    "postgresql",
    "database",
    "platform",
  ]
}
