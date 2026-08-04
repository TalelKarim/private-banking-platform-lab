resource "aws_ebs_volume" "lab_data" {
  availability_zone = data.aws_subnet.selected.availability_zone

  type       = "gp3"
  size       = var.data_volume_size
  encrypted  = true
  iops       = 3000
  throughput = 125

  tags = {
    Name    = "${var.project_name}-data"
    Purpose = "OpenStack, Docker, images and nested VM data"
  }
}

resource "aws_instance" "lab" {
  ami           = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type = var.instance_type

  subnet_id                   = data.aws_subnet.selected.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.lab.id]

  key_name             = aws_key_pair.lab.key_name
  iam_instance_profile = aws_iam_instance_profile.lab.name

  # Important : l'EC2 doit pouvoir router du trafic pour les réseaux
  # OpenStack et les VM imbriquées.
  source_dest_check = false

  ebs_optimized = true
  monitoring    = false


  cpu_options {
    nested_virtualization = "enabled"
  }

  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
    iops                  = 3000
    throughput            = 125

    tags = {
      Name = "${var.project_name}-root"
    }
  }

  user_data = templatefile(
    "${path.module}/cloud-init/user-data.sh.tftpl",
    {
      data_volume_serial = replace(aws_ebs_volume.lab_data.id, "-", "")
    }
  )

  # Modifier le user-data ne doit pas détruire notre gros lab.
  user_data_replace_on_change = false

  tags = {
    Name = "${var.project_name}-host"
    Role = "OpenStack-All-In-One"
    OS   = "Ubuntu-24.04"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    local_sensitive_file.ssh_private_key
  ]
}

resource "aws_volume_attachment" "lab_data" {
  device_name = "/dev/sdf"

  volume_id   = aws_ebs_volume.lab_data.id
  instance_id = aws_instance.lab.id

  force_detach                   = false
  stop_instance_before_detaching = true
}