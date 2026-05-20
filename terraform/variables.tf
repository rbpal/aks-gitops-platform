# ---- Sandbox identity (you fill these in terraform.tfvars) ----

variable "subscription_id" {
  description = "Sandbox subscription ID. Get it with: az account show --query id -o tsv"
  type        = string

  validation {
    condition     = length(var.subscription_id) > 0
    error_message = "Set subscription_id in terraform.tfvars (from your Pluralsight sandbox)."
  }
}

variable "tenant_id" {
  description = "Sandbox tenant ID. Get it with: az account show --query tenantId -o tsv"
  type        = string

  validation {
    condition     = length(var.tenant_id) > 0
    error_message = "Set tenant_id in terraform.tfvars (from your Pluralsight sandbox)."
  }
}

variable "resource_group_name" {
  description = "Existing resource group the sandbox gives you. List with: az group list -o table"
  type        = string

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "Set resource_group_name in terraform.tfvars to the RG your sandbox provides."
  }
}

# ---- Lab knobs (sensible defaults; override in tfvars if needed) ----

variable "prefix" {
  description = "Short, lowercase, alphanumeric prefix for resource names."
  type        = string
  default     = "aksgitops"
}

variable "kubernetes_version" {
  description = <<-EOT
    AKS K8s minor version. Left null so apply uses a sandbox-supported default.
    BEST PRACTICE is to pin: az aks get-versions -l <region> --query 'values[].version' -o table
  EOT
  type        = string
  default     = null
}

variable "node_count" {
  description = "System node pool count. Sandbox caps this at 3. Drop to 1 if vCPU quota is tight."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 3
    error_message = "Pluralsight sandbox allows max 3 nodes per cluster. Set node_count between 1 and 3."
  }
}

variable "node_vm_size" {
  description = "Node VM size. Try Standard_B2as_v2 if B2s is out of capacity."
  type        = string
  default     = "Standard_B2s"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    env     = "lab"
    purpose = "aks-gitops-lab"
  }
}
