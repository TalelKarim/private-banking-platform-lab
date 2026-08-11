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
