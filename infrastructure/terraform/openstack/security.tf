resource "openstack_networking_secgroup_v2" "management" {
  name                 = var.management_security_group_name
  description          = "Baseline management access for private banking lab workloads"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "management_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.management_source_cidr
  security_group_id = openstack_networking_secgroup_v2.management.id
}

resource "openstack_networking_secgroup_rule_v2" "management_ssh_ops_runner" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ops_runner_management_cidr
  security_group_id = openstack_networking_secgroup_v2.management.id
}

resource "openstack_networking_secgroup_rule_v2" "management_icmp_external" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.management_source_cidr
  security_group_id = openstack_networking_secgroup_v2.management.id
}

resource "openstack_networking_secgroup_rule_v2" "management_icmp_private" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.management.id
}

resource "openstack_networking_secgroup_rule_v2" "management_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.management.id
}

resource "openstack_networking_secgroup_v2" "jenkins" {
  name                 = var.jenkins_security_group_name
  description          = "Jenkins controller application access"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_ui_external" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = var.management_source_cidr
  security_group_id = openstack_networking_secgroup_v2.jenkins.id
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_ui_private" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.jenkins.id
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.jenkins.id
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_ui_edge_gateway" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = var.edge_gateway_source_cidr
  security_group_id = openstack_networking_secgroup_v2.jenkins.id
}
