variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to deploy the network into."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "vnet_address_space" {
  description = "VNet CIDR. With Azure CNI Overlay, pods do NOT consume this — only nodes do."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "node_subnet_prefix" {
  description = "Subnet CIDR holding AKS node IPs (~250 in a /24)."
  type        = list(string)
  default     = ["10.10.1.0/24"]
}

variable "tags" {
  description = "Tags applied to network resources."
  type        = map(string)
  default     = {}
}
