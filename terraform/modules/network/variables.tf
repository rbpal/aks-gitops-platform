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

# ---- HUB (firewall) ----
variable "hub_address_space" {
  description = "Hub VNet CIDR (hosts Azure Firewall)."
  type        = list(string)
  default     = ["10.10.0.0/24"]
}

variable "firewall_subnet_prefix" {
  description = "CIDR for AzureFirewallSubnet (data plane). Min /26; name fixed by Azure."
  type        = list(string)
  default     = ["10.10.0.0/26"]
}

variable "firewall_mgmt_subnet_prefix" {
  description = "CIDR for AzureFirewallManagementSubnet (Basic SKU requirement). Min /26; name fixed."
  type        = list(string)
  default     = ["10.10.0.64/26"]
}

variable "firewall_private_ip" {
  description = "Hub firewall private IP — first usable in AzureFirewallSubnet (10.10.0.0/26 => 10.10.0.4). The spoke 0/0 route points here."
  type        = string
  default     = "10.10.0.4"
}

# ---- SPOKE (workloads) ----
variable "spoke_address_space" {
  description = "Spoke VNet CIDR (AKS + LB frontend + PEs). Must not overlap the hub."
  type        = list(string)
  default     = ["10.11.0.0/16"]
}

variable "node_subnet_prefix" {
  description = "CIDR for aks-nodes — AKS node IPs (= LB backend pool; ~250 in a /24)."
  type        = list(string)
  default     = ["10.11.1.0/24"]
}

variable "pe_subnet_prefix" {
  description = "CIDR for peSubnet — Private Endpoints for Key Vault + Service Bus."
  type        = list(string)
  default     = ["10.11.4.0/24"]
}

variable "tags" {
  description = "Tags applied to network resources."
  type        = map(string)
  default     = {}
}
