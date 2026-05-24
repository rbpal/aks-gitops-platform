variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Front Door profile (Front Door itself is global)."
  type        = string
}

variable "origin_host" {
  description = "Origin host Front Door forwards to — the Azure Firewall DATA public IP."
  type        = string
}

variable "health_probe_path" {
  description = "Origin health-probe path (served by the app through the ingress)."
  type        = string
  default     = "/healthz"
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
