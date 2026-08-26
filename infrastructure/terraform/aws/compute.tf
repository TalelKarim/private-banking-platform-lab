resource "aws_ebs_volume" "lab_data" {
  count = local.use_golden_ami ? 0 : 1

  availability_zone = data.aws_subnet.selected.availability_zone

  type       = "gp3"
  size       = var.data_volume_size
  encrypted  = true
  iops       = 3000
  throughput = 125

  tags = {
    Name    = "${var.project_name}-data"
    Purpose = "Docker, Kolla, Glance, Nova ephemeral disks and repository data"
  }
}

resource "aws_ebs_volume" "cinder" {
  count = local.use_golden_ami ? 0 : 1

  availability_zone = data.aws_subnet.selected.availability_zone

  type       = "gp3"
  size       = var.cinder_volume_size
  encrypted  = true
  iops       = 3000
  throughput = 125

  tags = {
    Name    = "${var.project_name}-cinder"
    Purpose = "Dedicated raw block device for the OpenStack Cinder LVM backend"
  }
}

resource "aws_instance" "lab" {
  ami           = local.use_golden_ami ? var.golden_ami_id : data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type = var.instance_type

  subnet_id                   = data.aws_subnet.selected.id
  private_ip                  = var.openstack_host_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.lab.id]

  key_name             = aws_key_pair.lab.key_name
  iam_instance_profile = aws_iam_instance_profile.lab.name

  # The EC2 host routes traffic for nested OpenStack networks.
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

  # In Golden-AMI mode the AMI already carries /data and Cinder snapshots.
  # Override those mappings at instance launch so /data can grow beyond the
  # snapshot size while preserving its filesystem and OpenStack contents.
  dynamic "ebs_block_device" {
    for_each = local.use_golden_ami ? local.golden_runtime_block_devices : {}

    content {
      device_name           = ebs_block_device.key
      snapshot_id           = ebs_block_device.value.snapshot_id
      volume_type           = "gp3"
      volume_size           = local.golden_runtime_volume_sizes[ebs_block_device.key]
      delete_on_termination = true
      iops                  = 3000
      throughput            = 125

      tags = {
        Name = ebs_block_device.key == "/dev/sdf" ? "${var.project_name}-data" : "${var.project_name}-cinder"
      }
    }
  }

  # Bootstrap mode provisions fresh data/Cinder EBS volumes and discovers them
  # from Terraform-known volume IDs. Golden mode restores those EBS volumes
  # from the AMI snapshots, then refreshes their new EC2 volume serials locally.
  user_data = local.use_golden_ami ? file(
    "${path.module}/cloud-init/golden-user-data.sh"
    ) : templatefile(
    "${path.module}/cloud-init/user-data.sh.tftpl",
    {
      data_volume_serial   = replace(aws_ebs_volume.lab_data[0].id, "-", "")
      cinder_volume_serial = replace(aws_ebs_volume.cinder[0].id, "-", "")
    }
  )

  # Configuration after first boot is owned by Ansible, not cloud-init.
  user_data_replace_on_change = false

  # AWS validates that private_ip belongs to subnet_id when the instance is created.
  # Terraform has no built-in cidrcontains() function, so do not duplicate that
  # provider-side validation with a non-existent language function.

  tags = {
    Name = "${var.project_name}-host"
    Role = "OpenStack-All-In-One"
    OS   = "Ubuntu-24.04"
  }

  lifecycle {
    precondition {
      condition = local.use_golden_ami ? (
        toset(keys(local.golden_runtime_block_devices)) == toset(["/dev/sdf", "/dev/sdg"])
      ) : true
      error_message = "Golden AMI must contain exactly the baked /dev/sdf (/data) and /dev/sdg (Cinder) non-root mappings."
    }

    precondition {
      condition = local.use_golden_ami ? (
        var.data_volume_size >= try(local.golden_runtime_block_devices["/dev/sdf"].snapshot_size, 0) &&
        var.cinder_volume_size >= try(local.golden_runtime_block_devices["/dev/sdg"].snapshot_size, 0)
      ) : true
      error_message = "Runtime EBS sizes cannot be smaller than the Golden AMI snapshots."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    local_sensitive_file.ssh_private_key
  ]
}

resource "aws_volume_attachment" "lab_data" {
  count = local.use_golden_ami ? 0 : 1

  device_name = "/dev/sdf"

  volume_id   = aws_ebs_volume.lab_data[0].id
  instance_id = aws_instance.lab.id

  force_detach                   = false
  stop_instance_before_detaching = true
}

resource "aws_volume_attachment" "cinder" {
  count = local.use_golden_ami ? 0 : 1

  device_name = "/dev/sdg"

  volume_id   = aws_ebs_volume.cinder[0].id
  instance_id = aws_instance.lab.id

  force_detach                   = false
  stop_instance_before_detaching = true
}
