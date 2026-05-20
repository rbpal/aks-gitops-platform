variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the cluster is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "aks_subnet_id" {
  description = "Subnet ID for the node pool (from the network module)."
  type        = string
}

variable "kubernetes_version" {
  description = "K8s minor version. null => AKS picks a supported default; pin in prod."
  type        = string
  default     = null
}

variable "node_count" {
  description = "System node pool count."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "Node VM size (B2s = 2 vCPU/4GiB)."
  type        = string
  default     = "Standard_B2s"
}

variable "tags" {
  description = "Tags applied to the cluster."
  type        = map(string)
  default     = {}
}
