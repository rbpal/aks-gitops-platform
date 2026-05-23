variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Service Bus namespace."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
