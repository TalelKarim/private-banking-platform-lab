resource "aws_security_group" "lab" {
  name_prefix = "${var.project_name}-"
  description = "Security group for the private banking platform lab host"
  vpc_id      = data.aws_vpc.default.id

  revoke_rules_on_delete = true

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# SSH direct depuis ton Mac uniquement.
resource "aws_vpc_security_group_ingress_rule" "ssh_from_mac" {
  security_group_id = aws_security_group.lab.id

  description = "SSH from the current Mac public IPv4"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = local.effective_ssh_cidr
}

# SSH depuis le terminal navigateur EC2 Instance Connect.
resource "aws_vpc_security_group_ingress_rule" "ssh_from_instance_connect" {
  security_group_id = aws_security_group.lab.id

  description    = "SSH from the regional EC2 Instance Connect service"
  ip_protocol    = "tcp"
  from_port      = 22
  to_port        = 22
  prefix_list_id = data.aws_ec2_managed_prefix_list.instance_connect.id
}


# Openstack dashboard direct depuis ton Mac uniquement.
resource "aws_vpc_security_group_ingress_rule" "http_from_mac" {
  security_group_id = aws_security_group.lab.id

  description = "Openstack dashboards from the current Mac public IPv4"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = local.effective_ssh_cidr
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.lab.id

  description = "Allow outbound IPv4 traffic"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# The administration runner reaches the OpenStack control-plane only through
# the host's private VPC address. Security-group references keep these APIs
# closed to the Internet while allowing the dedicated runner to manage them.
locals {
  openstack_api_ports = {
    heat_cfn  = 8000
    heat      = 8004
    nova      = 8774
    cinder    = 8776
    placement = 8778
    glance    = 9292
    neutron   = 9696
    keystone  = 5000
  }
}

resource "aws_vpc_security_group_ingress_rule" "openstack_api_from_ops_runner" {
  for_each = local.openstack_api_ports

  security_group_id            = aws_security_group.lab.id
  referenced_security_group_id = aws_security_group.ops_runner.id

  description = "${each.key} API from the dedicated ops runner"
  ip_protocol = "tcp"
  from_port   = each.value
  to_port     = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_ops_runner" {
  security_group_id            = aws_security_group.lab.id
  referenced_security_group_id = aws_security_group.ops_runner.id

  description = "SSH from the dedicated ops runner to the lab host and routed OpenStack workload floating IPs"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

# Route the OpenStack provider network through the lab-host EC2. The lab host is
# a deliberate VPC middlebox (source_dest_check=false) and forwards this traffic
# through os-host <-> os-ext to Neutron. This single route covers every current
# and future workload floating IP allocated from public-net.
resource "aws_route" "openstack_external_via_lab_host" {
  route_table_id         = local.selected_route_table_id
  destination_cidr_block = var.openstack_external_network_cidr
  network_interface_id   = aws_instance.lab.primary_network_interface_id
}

# Application traffic from the dedicated edge is allowed to cross the lab-host
# only on explicit backend ports. The lab-host remains a router, not a proxy.
resource "aws_vpc_security_group_ingress_rule" "openstack_backend_from_edge" {
  for_each = {
    for port in var.edge_backend_tcp_ports :
    tostring(port) => port
  }
  security_group_id = aws_security_group.lab.id
  # This is routed/middlebox traffic. Use the edge private IP explicitly rather
  # than a security-group reference so the source match remains unambiguous.
  cidr_ipv4   = "${var.edge_gateway_private_ip}/32"
  description = "OpenStack backend TCP/${each.value} transit from the edge gateway private IP"
  ip_protocol = "tcp"
  from_port   = each.value
  to_port     = each.value
}
