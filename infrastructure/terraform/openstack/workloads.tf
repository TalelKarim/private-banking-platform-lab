module "jenkins_controller" {
  source = "./modules/compute-instance"

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
