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
  default     = "r8i.4xlarge"
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
  description = "Persistent data EBS volume size in GiB for Docker, Kolla, Glance and Nova root disks"
  type        = number
  default     = 600

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

variable "openstack_external_network_cidr" {
  description = "OpenStack provider-network CIDR routed by the VPC to the lab-host ENI"
  type        = string
  default     = "192.168.250.0/24"

  validation {
    condition     = can(cidrnetmask(var.openstack_external_network_cidr))
    error_message = "openstack_external_network_cidr must be a valid IPv4 CIDR."
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

variable "workload_ssh_private_key_ssm_parameter_name" {
  description = "Existing SSM SecureString containing the private SSH key used by Ansible to manage OpenStack workload VMs"
  type        = string
  default     = "/private-banking-platform-lab/openstack/workload-ssh-private-key"

  validation {
    condition     = startswith(var.workload_ssh_private_key_ssm_parameter_name, "/") && length(var.workload_ssh_private_key_ssm_parameter_name) > 1
    error_message = "workload_ssh_private_key_ssm_parameter_name must be an absolute SSM parameter path."
  }
}
variable "jenkins_admin_password_ssm_parameter_name" {
  description = "Existing SSM SecureString containing the Jenkins bootstrap administrator password"
  type        = string
  default     = "/private-banking-platform-lab/jenkins/admin-password"

  validation {
    condition     = startswith(var.jenkins_admin_password_ssm_parameter_name, "/") && length(var.jenkins_admin_password_ssm_parameter_name) > 1
    error_message = "jenkins_admin_password_ssm_parameter_name must be an absolute SSM parameter path."
  }
}

variable "postgresql_app_password_ssm_parameter_name" {
  description = "SSM SecureString used by Ansible for the PostgreSQL portfolio application password"
  type        = string
  default     = "/private-banking-platform-lab/postgresql/portfolio-app-password"

  validation {
    condition     = startswith(var.postgresql_app_password_ssm_parameter_name, "/") && length(var.postgresql_app_password_ssm_parameter_name) > 1
    error_message = "postgresql_app_password_ssm_parameter_name must be an absolute SSM parameter path."
  }
}

variable "edge_gateway_instance_type" {
  description = "EC2 instance type used by the HTTP/HTTPS edge gateway"
  type        = string
  default     = "t3.micro"
}

variable "edge_gateway_root_volume_size" {
  description = "Root EBS volume size in GiB for the edge gateway"
  type        = number
  default     = 12
  validation {
    condition     = var.edge_gateway_root_volume_size >= 8
    error_message = "The edge gateway root volume must be at least 8 GiB."
  }
}

variable "edge_gateway_private_ip" {
  description = "Stable private IPv4 used by the edge gateway inside the selected AWS subnet"
  type        = string
  default     = "172.31.31.71"
  validation {
    condition     = can(cidrnetmask("${var.edge_gateway_private_ip}/32"))
    error_message = "edge_gateway_private_ip must be a valid IPv4 address."
  }
}

variable "edge_client_cidr" {
  description = "CIDR allowed to reach the edge gateway on HTTP/HTTPS. Null reuses the detected Mac public IPv4 CIDR."
  type        = string
  default     = null
  validation {
    condition     = var.edge_client_cidr == null || can(cidrnetmask(var.edge_client_cidr))
    error_message = "edge_client_cidr must be a valid IPv4 CIDR such as 82.10.20.30/32."
  }
}

variable "edge_backend_tcp_ports" {
  description = "OpenStack floating-IP TCP ports that the edge gateway may reach through the lab host"
  type        = set(number)
  default     = [443, 8080]
  validation {
    condition     = alltrue([for port in var.edge_backend_tcp_ports : port >= 1 && port <= 65535])
    error_message = "edge_backend_tcp_ports must contain valid TCP port numbers."
  }
}

variable "lab_ssh_private_key_ssm_parameter_name" {
  description = "SSM SecureString used temporarily by the ops-runner when Ansible manages AWS lab instances such as the edge gateway"
  type        = string
  default     = "/private-banking-platform-lab/aws/lab-ssh-private-key"
  validation {
    condition     = startswith(var.lab_ssh_private_key_ssm_parameter_name, "/") && length(var.lab_ssh_private_key_ssm_parameter_name) > 1
    error_message = "lab_ssh_private_key_ssm_parameter_name must be an absolute SSM parameter path."
  }
}
