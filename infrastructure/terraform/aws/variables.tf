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