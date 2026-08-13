variable "external_network_name" {
  description = "Name of the OpenStack provider/external network"
  type        = string
  default     = "public-net"
}

variable "external_subnet_name" {
  description = "Name of the OpenStack provider/external subnet"
  type        = string
  default     = "public-subnet"
}

variable "external_physical_network" {
  description = "Neutron physical network mapped by Kolla to the external OVS bridge"
  type        = string
  default     = "physnet1"
}

variable "external_network_cidr" {
  description = "CIDR carried by the OpenStack external provider network"
  type        = string
  default     = "192.168.250.0/24"

  validation {
    condition     = can(cidrnetmask(var.external_network_cidr))
    error_message = "external_network_cidr must be a valid IPv4 CIDR."
  }
}

variable "external_gateway_ip" {
  description = "Linux os-host address acting as the gateway for the OpenStack external subnet"
  type        = string
  default     = "192.168.250.1"

  validation {
    condition     = can(cidrnetmask("${var.external_gateway_ip}/32"))
    error_message = "external_gateway_ip must be a valid IPv4 address."
  }
}

variable "external_allocation_pool_start" {
  description = "First floating/provider IP available for allocation"
  type        = string
  default     = "192.168.250.100"
}

variable "external_allocation_pool_end" {
  description = "Last floating/provider IP available for allocation"
  type        = string
  default     = "192.168.250.199"
}

variable "private_network_name" {
  description = "Name of the tenant network used by lab workloads"
  type        = string
  default     = "private-net"
}

variable "private_subnet_name" {
  description = "Name of the tenant subnet used by lab workloads"
  type        = string
  default     = "private-subnet"
}

variable "private_network_cidr" {
  description = "Tenant CIDR used by OpenStack workload VMs"
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.private_network_cidr))
    error_message = "private_network_cidr must be a valid IPv4 CIDR."
  }
}

variable "private_gateway_ip" {
  description = "Neutron router gateway on the private tenant subnet"
  type        = string
  default     = "10.10.0.1"

  validation {
    condition     = can(cidrnetmask("${var.private_gateway_ip}/32"))
    error_message = "private_gateway_ip must be a valid IPv4 address."
  }
}

variable "private_dns_nameservers" {
  description = "DNS resolvers advertised by Neutron DHCP to workload VMs"
  type        = list(string)
  default     = ["1.1.1.1"]
}

variable "router_name" {
  description = "Name of the Neutron router connecting private and external networks"
  type        = string
  default     = "lab-router"
}

variable "management_security_group_name" {
  description = "Name of the baseline security group attached to administrable workloads"
  type        = string
  default     = "lab-management"
}

variable "management_source_cidr" {
  description = "CIDR allowed to reach workload management ports through the OpenStack external network"
  type        = string
  default     = "192.168.250.0/24"

  validation {
    condition     = can(cidrnetmask(var.management_source_cidr))
    error_message = "management_source_cidr must be a valid IPv4 CIDR."
  }
}

variable "ops_runner_management_cidr" {
  description = "AWS subnet CIDR whose ops-runner may SSH to workload floating IPs through the lab-host router"
  type        = string
  default     = "172.31.16.0/20"

  validation {
    condition     = can(cidrnetmask(var.ops_runner_management_cidr))
    error_message = "ops_runner_management_cidr must be a valid IPv4 CIDR."
  }
}

variable "small_flavor_name" {
  description = "Name of the baseline small Nova flavor"
  type        = string
  default     = "lab.small"
}

variable "small_flavor_ram_mb" {
  description = "RAM in MiB assigned to the baseline small Nova flavor"
  type        = number
  default     = 2048
}

variable "small_flavor_vcpus" {
  description = "vCPU count assigned to the baseline small Nova flavor"
  type        = number
  default     = 2
}

variable "small_flavor_disk_gb" {
  description = "Root disk size in GiB assigned to the baseline small Nova flavor"
  type        = number
  default     = 10
}

variable "medium_flavor_name" {
  description = "Name of the reusable medium Nova flavor"
  type        = string
  default     = "lab.medium"
}

variable "medium_flavor_ram_mb" {
  description = "RAM in MiB assigned to the reusable medium Nova flavor"
  type        = number
  default     = 4096
}

variable "medium_flavor_vcpus" {
  description = "vCPU count assigned to the reusable medium Nova flavor"
  type        = number
  default     = 2
}

variable "medium_flavor_disk_gb" {
  description = "Root disk size in GiB assigned to the reusable medium Nova flavor"
  type        = number
  default     = 20
}

variable "ubuntu_image_name" {
  description = "Name of the Terraform-managed Ubuntu 24.04 Glance base image"
  type        = string
  default     = "ubuntu-24.04-noble-amd64-20260801"
}

variable "ubuntu_image_source_url" {
  description = "Pinned Canonical Ubuntu 24.04 cloud image used to populate Glance"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/noble/release-20260801/ubuntu-24.04-server-cloudimg-amd64.img"

  validation {
    condition     = startswith(var.ubuntu_image_source_url, "https://")
    error_message = "ubuntu_image_source_url must use HTTPS."
  }
}

variable "workload_keypair_name" {
  description = "Nova keypair name shared by Terraform-managed lab workloads"
  type        = string
  default     = "private-banking-lab-workloads"
}

variable "workload_ssh_public_key" {
  description = "OpenSSH public key injected into Terraform-managed workload VMs; set this in the HCP Terraform workspace"
  type        = string
  sensitive   = true

  validation {
    condition = anytrue([
      startswith(trimspace(var.workload_ssh_public_key), "ssh-rsa "),
      startswith(trimspace(var.workload_ssh_public_key), "ssh-ed25519 "),
      startswith(trimspace(var.workload_ssh_public_key), "ecdsa-sha2-"),
    ])
    error_message = "workload_ssh_public_key must be an OpenSSH-formatted public key."
  }
}

variable "jenkins_instance_name" {
  description = "Name of the persistent Jenkins controller VM"
  type        = string
  default     = "jenkins-controller"
}

variable "jenkins_fixed_ip" {
  description = "Stable private IPv4 assigned to the Jenkins controller"
  type        = string
  default     = "10.10.0.20"

  validation {
    condition     = can(cidrnetmask("${var.jenkins_fixed_ip}/32"))
    error_message = "jenkins_fixed_ip must be a valid IPv4 address."
  }
}

variable "jenkins_data_volume_size_gb" {
  description = "Persistent Cinder volume size reserved for Jenkins home and build state"
  type        = number
  default     = 30

  validation {
    condition     = var.jenkins_data_volume_size_gb >= 20
    error_message = "jenkins_data_volume_size_gb must be at least 20 GiB."
  }
}

variable "jenkins_security_group_name" {
  description = "Name of the Jenkins application security group"
  type        = string
  default     = "jenkins-controller"
}
