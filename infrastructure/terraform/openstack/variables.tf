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

variable "edge_gateway_source_cidr" {
  description = "Stable AWS edge-gateway address allowed to reach web workloads through floating IPs"
  type        = string
  default     = "172.31.31.71/32"
  validation {
    condition     = can(cidrnetmask(var.edge_gateway_source_cidr))
    error_message = "edge_gateway_source_cidr must be a valid IPv4 CIDR."
  }
}

variable "jenkins_worker_instance_name" {
  description = "Name of the dedicated Jenkins build worker VM"
  type        = string
  default     = "jenkins-agent-01"
}

variable "jenkins_worker_fixed_ip" {
  description = "Stable private IPv4 assigned to the Jenkins build worker"
  type        = string
  default     = "10.10.0.30"

  validation {
    condition     = can(cidrnetmask("${var.jenkins_worker_fixed_ip}/32"))
    error_message = "jenkins_worker_fixed_ip must be a valid IPv4 address."
  }
}

variable "jenkins_worker_security_group_name" {
  description = "Name of the Jenkins worker security group"
  type        = string
  default     = "jenkins-worker"
}

variable "postgresql_instance_name" {
  description = "Name of the PostgreSQL platform VM"
  type        = string
  default     = "postgresql"
}

variable "postgresql_fixed_ip" {
  description = "Stable private IPv4 assigned to the PostgreSQL VM"
  type        = string
  default     = "10.10.0.40"

  validation {
    condition     = can(cidrnetmask("${var.postgresql_fixed_ip}/32"))
    error_message = "postgresql_fixed_ip must be a valid IPv4 address."
  }
}

variable "postgresql_data_volume_size_gb" {
  description = "Persistent Cinder volume size reserved for PostgreSQL data"
  type        = number
  default     = 20

  validation {
    condition     = var.postgresql_data_volume_size_gb >= 10
    error_message = "postgresql_data_volume_size_gb must be at least 10 GiB."
  }
}

variable "postgresql_security_group_name" {
  description = "Name of the PostgreSQL application security group"
  type        = string
  default     = "postgresql"
}

variable "openshift_network_name" {
  description = "Name of the dedicated OpenStack tenant network used by OKD/OpenShift machines"
  type        = string
  default     = "openshift-net"
}

variable "openshift_subnet_name" {
  description = "Name of the dedicated subnet used by OKD/OpenShift machines"
  type        = string
  default     = "openshift-subnet"
}

variable "openshift_machine_network_cidr" {
  description = "Machine network CIDR assigned to OpenShift infrastructure VMs"
  type        = string
  default     = "10.20.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.openshift_machine_network_cidr))
    error_message = "openshift_machine_network_cidr must be a valid IPv4 CIDR."
  }
}

variable "openshift_gateway_ip" {
  description = "Neutron router gateway on the OpenShift machine subnet"
  type        = string
  default     = "10.20.0.1"

  validation {
    condition     = can(cidrnetmask("${var.openshift_gateway_ip}/32"))
    error_message = "openshift_gateway_ip must be a valid IPv4 address."
  }
}

variable "openshift_allocation_pool_start" {
  description = "First DHCP-allocatable address on openshift-subnet; lower addresses stay reserved for fixed infrastructure IPs"
  type        = string
  default     = "10.20.0.100"
}

variable "openshift_allocation_pool_end" {
  description = "Last DHCP-allocatable address on openshift-subnet"
  type        = string
  default     = "10.20.0.199"
}


variable "okd_control_flavor_name" {
  description = "Nova flavor used by compact OKD control-plane/worker nodes and the temporary bootstrap machine"
  type        = string
  default     = "okd.control"
}

variable "okd_control_flavor_ram_mb" {
  description = "RAM in MiB assigned to the compact OKD node flavor"
  type        = number
  default     = 16384
}

variable "okd_control_flavor_vcpus" {
  description = "vCPU count assigned to the compact OKD node flavor"
  type        = number
  default     = 4
}

variable "okd_control_flavor_disk_gb" {
  description = "Nova root disk size in GiB assigned to the compact OKD node flavor"
  type        = number
  default     = 100
}

variable "openshift_node_security_group_name" {
  description = "Security group reserved for bootstrap and compact OKD cluster nodes"
  type        = string
  default     = "openshift-nodes"
}

variable "okd_lb_security_group_name" {
  description = "Security group for the external-to-cluster OKD DNS/load-balancer VM"
  type        = string
  default     = "okd-lb"
}

variable "okd_lb_instance_name" {
  description = "Name of the permanent OKD DNS/load-balancer VM"
  type        = string
  default     = "okd-lb"
}

variable "okd_lb_fixed_ip" {
  description = "Stable OpenShift machine-network address assigned to okd-lb"
  type        = string
  default     = "10.20.0.10"

  validation {
    condition     = can(cidrnetmask("${var.okd_lb_fixed_ip}/32"))
    error_message = "okd_lb_fixed_ip must be a valid IPv4 address."
  }
}

variable "okd_ignition_http_port" {
  description = "Private HTTP port reserved for runtime Ignition delivery during OKD installation"
  type        = number
  default     = 8080
}
