resource "openstack_networking_port_v2" "this" {
  name           = "${var.name}-port"
  description    = "Primary tenant port for ${var.name}"
  network_id     = var.network_id
  admin_state_up = true

  security_group_ids = var.security_group_ids
  tags               = var.tags

  fixed_ip {
    subnet_id  = var.subnet_id
    ip_address = var.fixed_ip
  }
}

resource "openstack_compute_instance_v2" "this" {
  name                = var.name
  image_id            = var.image_id
  flavor_id           = var.flavor_id
  key_pair            = var.key_pair
  stop_before_destroy = true
  metadata            = var.metadata
  tags                = var.tags

  network {
    port = openstack_networking_port_v2.this.id
  }
}

resource "openstack_blockstorage_volume_v3" "data" {
  count = var.data_volume_size_gb > 0 ? 1 : 0

  name        = "${var.name}-data"
  description = "Persistent application data for ${var.name}"
  size        = var.data_volume_size_gb

  metadata = merge(var.metadata, {
    attached_to = var.name
  })
}

resource "openstack_compute_volume_attach_v2" "data" {
  count = var.data_volume_size_gb > 0 ? 1 : 0

  instance_id = openstack_compute_instance_v2.this.id
  volume_id   = openstack_blockstorage_volume_v3.data[0].id
}

resource "openstack_networking_floatingip_v2" "this" {
  count = var.create_floating_ip ? 1 : 0

  pool        = var.external_network
  subnet_id   = var.external_subnet_id
  port_id     = openstack_networking_port_v2.this.id
  description = "Floating IP for ${var.name}"
  tags        = var.tags
}
