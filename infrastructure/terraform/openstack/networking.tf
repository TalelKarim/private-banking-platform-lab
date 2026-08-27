resource "openstack_networking_network_v2" "external" {
  name           = var.external_network_name
  admin_state_up = true
  external       = true

  segments {
    physical_network = var.external_physical_network
    network_type     = "flat"
  }
}

resource "openstack_networking_subnet_v2" "external" {
  name       = var.external_subnet_name
  network_id = openstack_networking_network_v2.external.id
  cidr       = var.external_network_cidr
  ip_version = 4
  gateway_ip = var.external_gateway_ip

  enable_dhcp = false

  allocation_pool {
    start = var.external_allocation_pool_start
    end   = var.external_allocation_pool_end
  }
}

resource "openstack_networking_network_v2" "private" {
  name           = var.private_network_name
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "private" {
  name       = var.private_subnet_name
  network_id = openstack_networking_network_v2.private.id
  cidr       = var.private_network_cidr
  ip_version = 4
  gateway_ip = var.private_gateway_ip

  enable_dhcp     = true
  dns_nameservers = var.private_dns_nameservers
}

resource "openstack_networking_router_v2" "lab" {
  name                = var.router_name
  admin_state_up      = true
  external_network_id = openstack_networking_network_v2.external.id
  enable_snat         = true

  # The external gateway needs an address from the provider subnet.
  # Make that ordering explicit so a fresh lab build is deterministic.
  depends_on = [openstack_networking_subnet_v2.external]
}

resource "openstack_networking_router_interface_v2" "private" {
  router_id = openstack_networking_router_v2.lab.id
  subnet_id = openstack_networking_subnet_v2.private.id
}

# OpenShift gets its own machine network. Jenkins/PostgreSQL remain on the
# shared-services subnet while OKD nodes, bootstrap and the cluster edge live
# behind a distinct Neutron routing boundary.
resource "openstack_networking_network_v2" "openshift" {
  name           = var.openshift_network_name
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "openshift" {
  name       = var.openshift_subnet_name
  network_id = openstack_networking_network_v2.openshift.id
  cidr       = var.openshift_machine_network_cidr
  ip_version = 4
  gateway_ip = var.openshift_gateway_ip

  enable_dhcp     = true
  dns_nameservers = [var.okd_lb_fixed_ip]

  # Keep the lower addresses deterministic for the permanent LB, temporary
  # bootstrap machine and compact control-plane nodes.
  allocation_pool {
    start = var.openshift_allocation_pool_start
    end   = var.openshift_allocation_pool_end
  }
}

resource "openstack_networking_router_interface_v2" "openshift" {
  router_id = openstack_networking_router_v2.lab.id
  subnet_id = openstack_networking_subnet_v2.openshift.id
}
