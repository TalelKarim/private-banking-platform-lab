output "instance_id" {
  description = "Nova instance ID"
  value       = openstack_compute_instance_v2.this.id
}

output "instance_name" {
  description = "Nova instance name"
  value       = openstack_compute_instance_v2.this.name
}

output "port_id" {
  description = "Primary Neutron port ID"
  value       = openstack_networking_port_v2.this.id
}

output "fixed_ip" {
  description = "Stable tenant IPv4 address"
  value       = var.fixed_ip
}

output "floating_ip" {
  description = "Allocated floating IP, or null when disabled"
  value       = try(openstack_networking_floatingip_v2.this[0].address, null)
}

output "data_volume_id" {
  description = "Persistent Cinder data volume ID, or null when disabled"
  value       = try(openstack_blockstorage_volume_v3.data[0].id, null)
}

output "data_volume_device" {
  description = "Guest device selected by Nova for the data volume"
  value       = try(openstack_compute_volume_attach_v2.data[0].device, null)
}
