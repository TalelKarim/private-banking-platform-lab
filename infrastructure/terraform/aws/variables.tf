variable "aws_region" {
  description = "AWS region hosting the lab"
  type        = string
  default     = "eu-south-2"
}

variable "project_name" {
  description = "Project name used for naming and tagging resources"
  type        = string
  default     = "private-banking-platform-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "instance_type" {
  description = "EC2 instance type used as the virtual datacenter host"
  type        = string
  default     = "r8i.2xlarge"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size >= 20
    error_message = "The root volume must be at least 20 GiB."
  }
}

variable "data_volume_size" {
  description = "Persistent data EBS volume size in GiB"
  type        = number
  default     = 200

  validation {
    condition     = var.data_volume_size >= 100
    error_message = "The data volume must be at least 100 GiB."
  }
}


variable "cinder_volume_size" {
  description = "Dedicated raw EBS volume size in GiB for the Cinder LVM backend"
  type        = number
  default     = 100

  validation {
    condition     = var.cinder_volume_size >= 50
    error_message = "The Cinder volume must be at least 50 GiB."
  }
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH from the Mac. Null automatically detects the current public IPv4 address."
  type        = string
  default     = null

  validation {
    condition     = var.ssh_cidr == null || can(cidrnetmask(var.ssh_cidr))
    error_message = "ssh_cidr must be a valid IPv4 CIDR such as 82.10.20.30/32."
  }
}

variable "subnet_id" {
  description = "Optional default-VPC subnet override. Null selects the first default subnet."
  type        = string
  default     = null

  validation {
    condition     = var.subnet_id == null || startswith(var.subnet_id, "subnet-")
    error_message = "subnet_id must start with subnet-."
  }
}

variable "openstack_host_private_ip" {
  description = "Stable private IPv4 used by the OpenStack all-in-one host. Kolla endpoints are baked with this address."
  type        = string
  default     = "172.31.31.70"

  validation {
    condition     = can(cidrnetmask("${var.openstack_host_private_ip}/32"))
    error_message = "openstack_host_private_ip must be a valid IPv4 address."
  }
}

variable "golden_ami_id" {
  description = "Optional baked OpenStack AMI. Null keeps bootstrap mode on the stock Ubuntu AMI."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.golden_ami_id == null || can(regex("^ami-[0-9a-f]+$", var.golden_ami_id))
    error_message = "golden_ami_id must be null or a valid AMI ID such as ami-0123456789abcdef0."
  }
}

variable "ops_runner_instance_type" {
  description = "EC2 instance type used by the Terraform and Ansible administration runner"
  type        = string
  default     = "t3.small"
}

variable "ops_runner_root_volume_size" {
  description = "Root EBS volume size in GiB for the administration runner"
  type        = number
  default     = 20

  validation {
    condition     = var.ops_runner_root_volume_size >= 16
    error_message = "The ops-runner root volume must be at least 16 GiB."
  }
}

variable "tfc_agent_version" {
  description = "Pinned HCP Terraform Agent version installed on the ops-runner"
  type        = string
  default     = "1.30.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.tfc_agent_version))
    error_message = "tfc_agent_version must be a semantic version such as 1.30.1."
  }
}

variable "tfc_agent_name" {
  description = "Display name registered by the ops-runner in the HCP Terraform agent pool"
  type        = string
  default     = "private-banking-ops-runner-01"

  validation {
    condition     = length(trimspace(var.tfc_agent_name)) > 0
    error_message = "tfc_agent_name must not be empty."
  }
}

variable "tfc_agent_token_ssm_parameter_name" {
  description = "Existing SSM Parameter Store SecureString containing the HCP Terraform agent-pool token. The secret value is intentionally not managed by Terraform."
  type        = string
  default     = "/private-banking-platform-lab/hcp-terraform/agent-token"

  validation {
    condition     = startswith(var.tfc_agent_token_ssm_parameter_name, "/") && length(var.tfc_agent_token_ssm_parameter_name) > 1
    error_message = "tfc_agent_token_ssm_parameter_name must be an absolute SSM parameter path such as /private-banking-platform-lab/hcp-terraform/agent-token."
  }
}
