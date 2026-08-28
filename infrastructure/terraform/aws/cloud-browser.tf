# Optional low-cost Windows workstation used only as a cloud-hosted browser.
#
# The instance has no inbound Internet rules. Interactive desktop access is
# provided through AWS Systems Manager Fleet Manager. Its Elastic IP is used as
# the stable source IPv4 when Chrome reaches the public lab ALB, allowing the
# ALB security group to trust only this /32 in addition to the normal client.

resource "aws_iam_role" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  name = "${var.project_name}-cloud-browser-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-cloud-browser-role" }
}

resource "aws_iam_role_policy_attachment" "cloud_browser_ssm_core" {
  count = var.cloud_browser_enabled ? 1 : 0

  role       = aws_iam_role.cloud_browser[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  name = "${var.project_name}-cloud-browser-instance-profile"
  role = aws_iam_role.cloud_browser[0].name
}

resource "aws_security_group" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  name_prefix            = "${var.project_name}-cloud-browser-"
  description            = "Outbound-only security group for the SSM-managed Windows cloud browser"
  vpc_id                 = data.aws_vpc.default.id
  revoke_rules_on_delete = true

  tags = { Name = "${var.project_name}-cloud-browser-sg" }
}

# No inbound 3389 rule is required: Fleet Manager reaches the Windows desktop
# through the SSM control/data channels initiated outbound by the instance.
resource "aws_vpc_security_group_egress_rule" "cloud_browser_all_ipv4" {
  count = var.cloud_browser_enabled ? 1 : 0

  security_group_id = aws_security_group.cloud_browser[0].id
  description       = "Allow browser, Windows Update and SSM outbound IPv4 traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  ami           = data.aws_ssm_parameter.windows_2022_ami[0].value
  instance_type = var.cloud_browser_instance_type

  subnet_id                   = data.aws_subnet.selected.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.cloud_browser[0].id]

  # Reuse the Terraform-owned key pair so the initial Administrator password
  # can be decrypted with infrastructure/terraform/aws/.keys/...pem.
  key_name             = aws_key_pair.lab.key_name
  iam_instance_profile = aws_iam_instance_profile.cloud_browser[0].name

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
    volume_size           = var.cloud_browser_root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125

    tags = { Name = "${var.project_name}-cloud-browser-root" }
  }

  # AWS Windows AMIs already contain SSM Agent. The bootstrap makes Remote
  # Desktop explicitly available to Fleet Manager and installs Chrome.
  user_data                   = file("${path.module}/cloud-init/cloud-browser-user-data.ps1")
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-cloud-browser"
    Role = "Cloud-Browser"
    OS   = "Windows-Server-2022"
  }

  depends_on = [aws_iam_role_policy_attachment.cloud_browser_ssm_core]
}

# A stable EIP has two jobs:
#   1. websites see a predictable public source IPv4;
#   2. the public ALB can whitelist exactly that /32.
resource "aws_eip" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  domain = "vpc"

  tags = { Name = "${var.project_name}-cloud-browser-eip" }
}

resource "aws_eip_association" "cloud_browser" {
  count = var.cloud_browser_enabled ? 1 : 0

  instance_id   = aws_instance.cloud_browser[0].id
  allocation_id = aws_eip.cloud_browser[0].id
}
