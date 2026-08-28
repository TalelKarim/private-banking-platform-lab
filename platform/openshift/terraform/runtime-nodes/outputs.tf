output "bootstrap" {
  description = "Temporary bootstrap machine, or null after bootstrap retirement"
  value = var.bootstrap_enabled ? {
    id       = openstack_compute_instance_v2.bootstrap[0].id
    name     = openstack_compute_instance_v2.bootstrap[0].name
    fixed_ip = var.bootstrap.ip
    port_id  = openstack_networking_port_v2.bootstrap[0].id
  } : null
}

output "bootstrap_enabled" {
  description = "Whether Terraform currently manages the temporary bootstrap machine"
  value       = var.bootstrap_enabled
}

output "control_planes" {
  description = "Compact OKD control-plane/worker machines"
  value = {
    for name, server in openstack_compute_instance_v2.control_plane :
    name => {
      id       = server.id
      fixed_ip = var.control_planes[name].ip
      port_id  = openstack_networking_port_v2.control_plane[name].id
    }
  }
}
