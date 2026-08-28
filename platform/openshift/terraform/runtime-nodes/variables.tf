variable "network_id" {
  description = "Existing Neutron network ID for the OKD machine network"
  type        = string
}

variable "subnet_id" {
  description = "Existing Neutron subnet ID for the OKD machine network"
  type        = string
}

variable "security_group_id" {
  description = "Existing openshift-nodes security group ID"
  type        = string
}

variable "image_id" {
  description = "Existing SCOS Glance image ID matched to the pinned OKD installer"
  type        = string
}

variable "flavor_id" {
  description = "Existing Nova flavor ID used by bootstrap and compact control planes"
  type        = string
}

variable "key_pair" {
  description = "Existing Nova keypair injected into the SCOS machines"
  type        = string
}

variable "bootstrap_enabled" {
  description = "Whether the temporary OKD bootstrap machine and port must exist"
  type        = bool
  default     = true
}

variable "bootstrap" {
  description = "Temporary bootstrap Nova machine definition"
  type = object({
    name          = string
    ip            = string
    ignition_path = string
  })
}

variable "control_planes" {
  description = "Compact three-node control-plane definitions"
  type = map(object({
    ip            = string
    ignition_path = string
  }))
}
