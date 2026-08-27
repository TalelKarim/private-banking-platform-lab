output "bootstrap" {
  description = "Temporary bootstrap machine"
  value = {
    id       = openstack_compute_instance_v2.bootstrap.id
    name     = openstack_compute_instance_v2.bootstrap.name
    fixed_ip = var.bootstrap.ip
    port_id  = openstack_networking_port_v2.bootstrap.id
  }
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
