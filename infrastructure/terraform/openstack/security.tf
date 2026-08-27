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

resource "openstack_networking_secgroup_v2" "jenkins_worker" {
  name                 = var.jenkins_worker_security_group_name
  description          = "Dedicated Jenkins build worker traffic"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "jenkins_worker_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.jenkins_worker.id
}

resource "openstack_networking_secgroup_v2" "postgresql" {
  name                 = var.postgresql_security_group_name
  description          = "PostgreSQL database traffic from private OpenStack workloads"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "postgresql_private" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.postgresql.id
}

resource "openstack_networking_secgroup_rule_v2" "postgresql_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.postgresql.id
}

# Bootstrap and compact OKD nodes need broad east-west connectivity while the
# cluster is being formed. This remains scoped to the dedicated machine CIDR;
# north-south entry points are exposed only through okd-lb below.
resource "openstack_networking_secgroup_v2" "openshift_nodes" {
  name                 = var.openshift_node_security_group_name
  description          = "East-west traffic for OKD bootstrap and compact cluster nodes"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "openshift_nodes_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.openshift_nodes.id
}

resource "openstack_networking_secgroup_rule_v2" "openshift_nodes_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.openshift_nodes.id
}

resource "openstack_networking_secgroup_v2" "okd_lb" {
  name                 = var.okd_lb_security_group_name
  description          = "DNS, API, Machine Config, Ignition and ingress entry point for OKD"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_udp_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_tcp_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_udp_shared_services" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_tcp_shared_services" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_api_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_api_shared_services" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_api_ops_runner" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.ops_runner_management_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_machine_config_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22623
  port_range_max    = 22623
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_ignition_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.okd_ignition_http_port
  port_range_max    = var.okd_ignition_http_port
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_http_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_https_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_http_edge" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.edge_gateway_source_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_https_edge" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.edge_gateway_source_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_egress_ipv4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_udp_ops_runner" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.ops_runner_management_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_dns_tcp_ops_runner" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = var.ops_runner_management_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_http_shared_services" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

resource "openstack_networking_secgroup_rule_v2" "okd_lb_https_shared_services" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = var.private_network_cidr
  security_group_id = openstack_networking_secgroup_v2.okd_lb.id
}

# Future OKD workloads leave the overlay through their node address when
# reaching the external PostgreSQL VM, so permit 5432 from the OpenShift
# machine network without exposing the database to the provider network.
resource "openstack_networking_secgroup_rule_v2" "postgresql_openshift" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = var.openshift_machine_network_cidr
  security_group_id = openstack_networking_secgroup_v2.postgresql.id
}
