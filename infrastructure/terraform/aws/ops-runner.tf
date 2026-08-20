resource "aws_iam_role" "ops_runner" {
  name = "${var.project_name}-ops-runner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ops-runner-role"
  }
}

resource "aws_iam_role_policy_attachment" "ops_runner_ssm_core" {
  role       = aws_iam_role.ops_runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ops_runner" {
  name = "${var.project_name}-ops-runner-instance-profile"
  role = aws_iam_role.ops_runner.name
}

resource "aws_iam_role_policy" "ops_runner_hcp_agent_token" {
  name = "${var.project_name}-ops-runner-hcp-agent-token"
  role = aws_iam_role.ops_runner.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.tfc_agent_token_ssm_parameter_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ops_runner_workload_ssh_key" {
  name = "${var.project_name}-ops-runner-workload-ssh-key"
  role = aws_iam_role.ops_runner.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.workload_ssh_private_key_ssm_parameter_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ops_runner_jenkins_admin_password" {
  name = "${var.project_name}-ops-runner-jenkins-admin-password"
  role = aws_iam_role.ops_runner.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.jenkins_admin_password_ssm_parameter_name}"
      }
    ]
  })
}

resource "aws_security_group" "ops_runner" {
  name_prefix = "${var.project_name}-ops-runner-"
  description = "Security group for the Terraform and Ansible administration runner"
  vpc_id      = data.aws_vpc.default.id

  revoke_rules_on_delete = true

  tags = {
    Name = "${var.project_name}-ops-runner-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ops_runner_ssh_from_mac" {
  security_group_id = aws_security_group.ops_runner.id

  description = "SSH from the current Mac public IPv4"
  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_ipv4   = local.effective_ssh_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ops_runner_ssh_from_instance_connect" {
  security_group_id = aws_security_group.ops_runner.id

  description    = "SSH from the regional EC2 Instance Connect service"
  ip_protocol    = "tcp"
  from_port      = 22
  to_port        = 22
  prefix_list_id = data.aws_ec2_managed_prefix_list.instance_connect.id
}

resource "aws_vpc_security_group_egress_rule" "ops_runner_all_ipv4" {
  security_group_id = aws_security_group.ops_runner.id

  description = "Allow outbound IPv4 traffic"
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_instance" "ops_runner" {
  ami           = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type = var.ops_runner_instance_type

  subnet_id                   = data.aws_subnet.selected.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ops_runner.id]

  key_name             = aws_key_pair.lab.key_name
  iam_instance_profile = aws_iam_instance_profile.ops_runner.name

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
    volume_size           = var.ops_runner_root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125

    tags = {
      Name = "${var.project_name}-ops-runner-root"
    }
  }

  # This host is an execution/admin node only. It deliberately has no nested
  # virtualization, no OpenStack data disks and no local Terraform state.
  user_data = templatefile(
    "${path.module}/cloud-init/ops-runner-user-data.sh.tftpl",
    {
      aws_region                                  = var.aws_region
      openstack_host_private_ip                   = var.openstack_host_private_ip
      tfc_agent_name                              = var.tfc_agent_name
      tfc_agent_token_ssm_parameter_name          = var.tfc_agent_token_ssm_parameter_name
      tfc_agent_version                           = var.tfc_agent_version
      workload_ssh_private_key_ssm_parameter_name = var.workload_ssh_private_key_ssm_parameter_name
    }
  )

  # The ops-runner is intentionally stateless. If its bootstrap definition
  # changes, replacing it is safer and more reproducible than mutating it in place.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-ops-runner"
    Role = "Terraform-Ansible-Runner"
    OS   = "Ubuntu-24.04"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ops_runner_ssm_core,
    aws_iam_role_policy.ops_runner_hcp_agent_token,
    aws_iam_role_policy.ops_runner_workload_ssh_key,
    aws_iam_role_policy.ops_runner_jenkins_admin_password,
    local_sensitive_file.ssh_private_key
  ]
}
