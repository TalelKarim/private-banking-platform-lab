resource "aws_iam_role" "edge_gateway" {
  name = "${var.project_name}-edge-gateway-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.project_name}-edge-gateway-role" }
}

resource "aws_iam_role_policy_attachment" "edge_gateway_ssm_core" {
  role       = aws_iam_role.edge_gateway.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "edge_gateway" {
  name = "${var.project_name}-edge-gateway-instance-profile"
  role = aws_iam_role.edge_gateway.name
}

resource "aws_security_group" "edge_gateway" {
  name_prefix = "${var.project_name}-edge-gateway-"
  description = "Security group for the HTTP/HTTPS edge gateway"
  vpc_id      = data.aws_vpc.default.id
  revoke_rules_on_delete = true
  tags = { Name = "${var.project_name}-edge-gateway-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "edge_gateway_http" {
  security_group_id = aws_security_group.edge_gateway.id
  description = "HTTP from the explicitly allowed lab client CIDR"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_ipv4   = local.effective_edge_client_cidr
}

resource "aws_vpc_security_group_ingress_rule" "edge_gateway_https" {
  security_group_id = aws_security_group.edge_gateway.id
  description = "HTTPS reserved for the Route53/TLS phase"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = local.effective_edge_client_cidr
}

resource "aws_vpc_security_group_ingress_rule" "edge_gateway_ssh_from_ops_runner" {
  security_group_id            = aws_security_group.edge_gateway.id
  referenced_security_group_id = aws_security_group.ops_runner.id
  description = "SSH administration from the dedicated ops runner only"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "edge_gateway_all_ipv4" {
  security_group_id = aws_security_group.edge_gateway.id
  description = "Allow outbound IPv4 traffic"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_instance" "edge_gateway" {
  ami           = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type = var.edge_gateway_instance_type
  subnet_id                   = data.aws_subnet.selected.id
  private_ip                  = var.edge_gateway_private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.edge_gateway.id]
  key_name             = aws_key_pair.lab.key_name
  iam_instance_profile = aws_iam_instance_profile.edge_gateway.name
  ebs_optimized = true
  monitoring    = false
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.edge_gateway_root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125
    tags = { Name = "${var.project_name}-edge-gateway-root" }
  }
  # Cloud-init bootstraps the OS only; Ansible owns Nginx and its routes.
  user_data = file("${path.module}/cloud-init/edge-gateway-user-data.sh")
  user_data_replace_on_change = true
  tags = {
    Name = "${var.project_name}-edge-gateway"
    Role = "HTTP-HTTPS-Edge-Gateway"
    OS   = "Ubuntu-24.04"
  }
  depends_on = [aws_iam_role_policy_attachment.edge_gateway_ssm_core, local_sensitive_file.ssh_private_key]
}

resource "aws_eip" "edge_gateway" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-edge-gateway-eip" }
}

resource "aws_eip_association" "edge_gateway" {
  instance_id   = aws_instance.edge_gateway.id
  allocation_id = aws_eip.edge_gateway.id
}
