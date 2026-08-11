resource "openstack_compute_flavor_v2" "small" {
  name      = var.small_flavor_name
  ram       = var.small_flavor_ram_mb
  vcpus     = var.small_flavor_vcpus
  disk      = var.small_flavor_disk_gb
  is_public = true
}
