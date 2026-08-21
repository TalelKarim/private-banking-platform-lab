data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "http" "current_public_ipv4" {
  url = "https://checkip.amazonaws.com/"

  request_headers = {
    Accept = "text/plain"
  }
}

locals {
  selected_subnet_id = (
    var.subnet_id != null
    ? var.subnet_id
    : sort(data.aws_subnets.default.ids)[0]
  )

  effective_ssh_cidr = (
    var.ssh_cidr != null
    ? var.ssh_cidr
    : "${chomp(data.http.current_public_ipv4.response_body)}/32"
  )

  effective_edge_client_cidr = (
    var.edge_client_cidr != null
    ? var.edge_client_cidr
    : local.effective_ssh_cidr
  )
}

data "aws_subnet" "selected" {
  id = local.selected_subnet_id
}

data "aws_route_tables" "selected_subnet" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.subnet-id"
    values = [data.aws_subnet.selected.id]
  }
}

data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  selected_route_table_id = (
    length(data.aws_route_tables.selected_subnet.ids) == 1
    ? data.aws_route_tables.selected_subnet.ids[0]
    : data.aws_route_table.main.id
  )
}

data "aws_ssm_parameter" "ubuntu_2404_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_ec2_managed_prefix_list" "instance_connect" {
  name = "com.amazonaws.${var.aws_region}.ec2-instance-connect"
}
locals {
  use_golden_ami = var.golden_ami_id != null
}
