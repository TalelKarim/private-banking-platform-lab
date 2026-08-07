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