output "external_network" {
  description = "OpenStack external/provider network foundation"
  value = {
    id                    = openstack_networking_network_v2.external.id
    name                  = openstack_networking_network_v2.external.name
    subnet_id             = openstack_networking_subnet_v2.external.id
    subnet_name           = openstack_networking_subnet_v2.external.name
    cidr                  = openstack_networking_subnet_v2.external.cidr
    gateway_ip            = openstack_networking_subnet_v2.external.gateway_ip
    physical_network      = var.external_physical_network
    allocation_pool_start = var.external_allocation_pool_start
    allocation_pool_end   = var.external_allocation_pool_end
  }
}

output "private_network" {
  description = "OpenStack tenant network foundation"
  value = {
    id          = openstack_networking_network_v2.private.id
    name        = openstack_networking_network_v2.private.name
    subnet_id   = openstack_networking_subnet_v2.private.id
    subnet_name = openstack_networking_subnet_v2.private.name
    cidr        = openstack_networking_subnet_v2.private.cidr
    gateway_ip  = openstack_networking_subnet_v2.private.gateway_ip
  }
}

output "router" {
  description = "Neutron router connecting the tenant network to the provider network"
  value = {
    id   = openstack_networking_router_v2.lab.id
    name = openstack_networking_router_v2.lab.name
  }
}

output "management_security_group" {
  description = "Baseline workload management security group"
  value = {
    id   = openstack_networking_secgroup_v2.management.id
    name = openstack_networking_secgroup_v2.management.name
  }
}

output "small_flavor" {
  description = "Baseline Nova flavor used by lightweight lab workloads"
  value = {
    id      = openstack_compute_flavor_v2.small.id
    name    = openstack_compute_flavor_v2.small.name
    ram_mb  = openstack_compute_flavor_v2.small.ram
    vcpus   = openstack_compute_flavor_v2.small.vcpus
    disk_gb = openstack_compute_flavor_v2.small.disk
  }
}

output "medium_flavor" {
  description = "Reusable medium Nova flavor for persistent platform services"
  value = {
    id      = openstack_compute_flavor_v2.medium.id
    name    = openstack_compute_flavor_v2.medium.name
    ram_mb  = openstack_compute_flavor_v2.medium.ram
    vcpus   = openstack_compute_flavor_v2.medium.vcpus
    disk_gb = openstack_compute_flavor_v2.medium.disk
  }
}

output "ubuntu_2404_image" {
  description = "Terraform-managed Ubuntu 24.04 Glance base image"
  value = {
    id     = openstack_images_image_v2.ubuntu_2404.id
    name   = openstack_images_image_v2.ubuntu_2404.name
    status = openstack_images_image_v2.ubuntu_2404.status
  }
}

output "workload_keypair" {
  description = "Nova keypair used by Terraform-managed workloads"
  value = {
    name        = openstack_compute_keypair_v2.workload.name
    fingerprint = openstack_compute_keypair_v2.workload.fingerprint
  }
}

output "jenkins_controller" {
  description = "First persistent OpenStack platform VM and its attached resources"
  value = {
    instance_id      = module.jenkins_controller.instance_id
    name             = module.jenkins_controller.instance_name
    fixed_ip         = module.jenkins_controller.fixed_ip
    floating_ip      = module.jenkins_controller.floating_ip
    port_id          = module.jenkins_controller.port_id
    data_volume_id   = module.jenkins_controller.data_volume_id
    data_volume_path = module.jenkins_controller.data_volume_device
  }
}

output "jenkins_worker" {
  description = "Dedicated Jenkins build worker and its network addresses"
  value = {
    instance_id = module.jenkins_worker.instance_id
    name        = module.jenkins_worker.instance_name
    fixed_ip    = module.jenkins_worker.fixed_ip
    floating_ip = module.jenkins_worker.floating_ip
    port_id     = module.jenkins_worker.port_id
  }
}

output "postgresql" {
  description = "PostgreSQL platform VM, management address and persistent Cinder volume"
  value = {
    instance_id      = module.postgresql.instance_id
    name             = module.postgresql.instance_name
    fixed_ip         = module.postgresql.fixed_ip
    floating_ip      = module.postgresql.floating_ip
    port_id          = module.postgresql.port_id
    data_volume_id   = module.postgresql.data_volume_id
    data_volume_path = module.postgresql.data_volume_device
  }
}

output "openshift_network" {
  description = "Dedicated OpenStack machine network reserved for OKD/OpenShift infrastructure"
  value = {
    id                    = openstack_networking_network_v2.openshift.id
    name                  = openstack_networking_network_v2.openshift.name
    subnet_id             = openstack_networking_subnet_v2.openshift.id
    subnet_name           = openstack_networking_subnet_v2.openshift.name
    cidr                  = openstack_networking_subnet_v2.openshift.cidr
    gateway_ip            = openstack_networking_subnet_v2.openshift.gateway_ip
    allocation_pool_start = var.openshift_allocation_pool_start
    allocation_pool_end   = var.openshift_allocation_pool_end
  }
}

output "okd_control_flavor" {
  description = "Nova flavor reserved for compact OKD control-plane/worker and bootstrap machines"
  value = {
    id      = openstack_compute_flavor_v2.okd_control.id
    name    = openstack_compute_flavor_v2.okd_control.name
    ram_mb  = openstack_compute_flavor_v2.okd_control.ram
    vcpus   = openstack_compute_flavor_v2.okd_control.vcpus
    disk_gb = openstack_compute_flavor_v2.okd_control.disk
  }
}

output "openshift_security_groups" {
  description = "Security groups prepared for the OKD nodes and cluster edge"
  value = {
    nodes = {
      id   = openstack_networking_secgroup_v2.openshift_nodes.id
      name = openstack_networking_secgroup_v2.openshift_nodes.name
    }
    load_balancer = {
      id   = openstack_networking_secgroup_v2.okd_lb.id
      name = openstack_networking_secgroup_v2.okd_lb.name
    }
  }
}

output "okd_lb" {
  description = "Permanent OKD DNS/load-balancer VM and its management addresses"
  value = {
    instance_id = openstack_compute_instance_v2.okd_lb.id
    name        = openstack_compute_instance_v2.okd_lb.name
    fixed_ip    = var.okd_lb_fixed_ip
    floating_ip = openstack_networking_floatingip_v2.okd_lb.address
    port_id     = openstack_networking_port_v2.okd_lb.id
  }
}
