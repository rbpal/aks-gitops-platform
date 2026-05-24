variable "prefix" {
  description = "Resource name prefix (include the region, e.g. aksgitops-eastus2)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the firewall."
  type        = string
}

variable "location" {
  description = "Azure region (eastus2 for primary, centralus for DR)."
  type        = string
}

variable "firewall_subnet_id" {
  description = "AzureFirewallSubnet ID (data plane)."
  type        = string
}

variable "firewall_mgmt_subnet_id" {
  description = "AzureFirewallManagementSubnet ID — REQUIRED by the Basic SKU."
  type        = string
}

variable "internal_lb_ip" {
  description = "Pinned internal-LB frontend IP that AzFW DNATs inbound 443 to (e.g. 10.10.2.4)."
  type        = string
}

variable "workload_source_cidrs" {
  description = "Source CIDRs for egress rules — the node subnet(s)."
  type        = list(string)
}

variable "frontdoor_source_addresses" {
  description = "DNAT source lock. Set to your Front Door backend IPs (IP group) in prod; '*' for the lab (origin still locked at the ingress via X-Azure-FDID)."
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
