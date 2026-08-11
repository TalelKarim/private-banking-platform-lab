output "smoke_test_security_group_id" {
  description = "ID of the OpenStack security group created by the HCP Terraform smoke test."
  value       = openstack_networking_secgroup_v2.hcp_smoke_test.id
}

output "smoke_test_security_group_name" {
  description = "Name of the OpenStack security group created by the HCP Terraform smoke test."
  value       = openstack_networking_secgroup_v2.hcp_smoke_test.name
}