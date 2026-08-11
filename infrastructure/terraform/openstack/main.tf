resource "openstack_networking_secgroup_v2" "hcp_smoke_test_two" {
  name        = "hcp-terraform-smoke-test2"
  description = "Temporary security group used to validate HCP Terraform agent execution"
}