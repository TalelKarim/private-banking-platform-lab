resource "openstack_compute_flavor_v2" "small" {
  name      = var.small_flavor_name
  ram       = var.small_flavor_ram_mb
  vcpus     = var.small_flavor_vcpus
  disk      = var.small_flavor_disk_gb
  is_public = true
}

resource "openstack_compute_flavor_v2" "medium" {
  name      = var.medium_flavor_name
  ram       = var.medium_flavor_ram_mb
  vcpus     = var.medium_flavor_vcpus
  disk      = var.medium_flavor_disk_gb
  is_public = true
}

resource "openstack_compute_flavor_v2" "okd_control" {
  name      = var.okd_control_flavor_name
  ram       = var.okd_control_flavor_ram_mb
  vcpus     = var.okd_control_flavor_vcpus
  disk      = var.okd_control_flavor_disk_gb
  is_public = true
}
