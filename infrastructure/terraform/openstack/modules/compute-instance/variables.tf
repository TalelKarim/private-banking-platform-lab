variable "name" {
  description = "Nova instance name"
  type        = string
}

variable "image_id" {
  description = "Glance image ID used to boot the instance"
  type        = string
}

variable "flavor_id" {
  description = "Nova flavor ID used by the instance"
  type        = string
}

variable "key_pair" {
  description = "Nova keypair name injected into the instance"
  type        = string
}

variable "network_id" {
  description = "Neutron tenant network ID"
  type        = string
}

variable "subnet_id" {
  description = "Neutron tenant subnet ID"
  type        = string
}

variable "fixed_ip" {
  description = "Stable fixed IPv4 address assigned to the instance port"
  type        = string
}

variable "security_group_ids" {
  description = "Neutron security group IDs attached to the instance port"
  type        = list(string)
}

variable "create_floating_ip" {
  description = "Whether to allocate a floating IP for the instance"
  type        = bool
  default     = false
}

variable "external_network" {
  description = "External Neutron network name used for floating IP allocation"
  type        = string
  default     = null
}

variable "external_subnet_id" {
  description = "External Neutron subnet ID used for floating IP allocation"
  type        = string
  default     = null
}

variable "data_volume_size_gb" {
  description = "Persistent Cinder data volume size; zero disables the volume"
  type        = number
  default     = 0

  validation {
    condition     = var.data_volume_size_gb >= 0
    error_message = "data_volume_size_gb must be zero or greater."
  }
}

variable "metadata" {
  description = "Nova metadata associated with the instance"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags associated with the instance, port and floating IP"
  type        = set(string)
  default     = []
}
