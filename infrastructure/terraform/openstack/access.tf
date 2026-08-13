resource "openstack_compute_keypair_v2" "workload" {
  name       = var.workload_keypair_name
  public_key = trimspace(var.workload_ssh_public_key)
}
