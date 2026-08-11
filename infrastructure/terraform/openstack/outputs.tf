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
