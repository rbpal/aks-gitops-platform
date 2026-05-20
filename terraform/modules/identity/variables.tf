variable "prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the Key Vault + managed identity."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID (for the Key Vault + access policies)."
  type        = string
}

variable "admin_object_id" {
  description = "Object ID of the deploying user — gets an access policy so Terraform can write the test secret and you can read it for debugging."
  type        = string
}

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer URL — the issuer half of the federated credential."
  type        = string
}

variable "sa_namespace" {
  description = "K8s namespace of the ServiceAccount that will use this identity."
  type        = string
  default     = "default"
}

variable "sa_name" {
  description = "K8s ServiceAccount name. Must match the SA annotation + pod in k8s/."
  type        = string
  default     = "keyvault-reader"
}

variable "secret_name" {
  description = "Name of the demo secret."
  type        = string
  default     = "demo-secret"
}

variable "secret_value" {
  description = "Value of the demo secret (a throwaway string for the lab)."
  type        = string
  default     = "hello-from-key-vault"
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
