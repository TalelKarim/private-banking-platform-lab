# Runtime OKD machines are deliberately split from the HCP-managed OpenStack
# foundation. They cannot exist until openshift-install has generated fresh
# Ignition assets and those assets are reachable on okd-lb.

resource "openstack_networking_port_v2" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0

  name           = "${var.bootstrap.name}-port"
  description    = "Temporary OKD bootstrap port"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.security_group_id]

  fixed_ip {
    subnet_id  = var.subnet_id
    ip_address = var.bootstrap.ip
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "bootstrap",
    "runtime",
  ]
}

resource "openstack_compute_instance_v2" "bootstrap" {
  count = var.bootstrap_enabled ? 1 : 0

  name                = var.bootstrap.name
  image_id            = var.image_id
  flavor_id           = var.flavor_id
  key_pair            = var.key_pair
  stop_before_destroy = true

  # SCOS/OpenStack Ignition can read instance userdata from the metadata
  # service or config drive. Enabling a config drive makes that first-boot
  # handoff explicit and independent of Neutron metadata-agent timing.
  config_drive = true
  user_data    = file(var.bootstrap.ignition_path)

  metadata = {
    environment = "lab"
    role        = "okd-bootstrap"
    managed_by  = "terraform-runtime"
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "bootstrap",
    "runtime",
  ]

  network {
    port = openstack_networking_port_v2.bootstrap[0].id
  }
}

resource "openstack_networking_port_v2" "control_plane" {
  for_each = var.control_planes

  name           = "${each.key}-port"
  description    = "Compact OKD control-plane port for ${each.key}"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = [var.security_group_id]

  fixed_ip {
    subnet_id  = var.subnet_id
    ip_address = each.value.ip
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "control-plane",
    "worker",
    "runtime",
  ]
}

resource "openstack_compute_instance_v2" "control_plane" {
  for_each = var.control_planes

  name                = each.key
  image_id            = var.image_id
  flavor_id           = var.flavor_id
  key_pair            = var.key_pair
  stop_before_destroy = true

  config_drive = true
  user_data    = file(each.value.ignition_path)

  metadata = {
    environment = "lab"
    role        = "okd-control-plane-worker"
    managed_by  = "terraform-runtime"
  }

  tags = [
    "lab",
    "okd",
    "openshift",
    "control-plane",
    "worker",
    "runtime",
  ]

  network {
    port = openstack_networking_port_v2.control_plane[each.key].id
  }
}
