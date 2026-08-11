resource "openstack_networking_secgroup_v2" "hcp_smoke_test" {
  name        = "hcp-terraform-smoke-test"
  description = "Temporary security group used to validate HCP Terraform agent execution"
}