terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # --- State backend ---
  # SANDBOX MODE: local state (no backend block). The Pluralsight sandbox is
  # ephemeral; a remote backend would reset with it. State -> ./terraform.tfstate
  # (gitignored). Tear down with `terraform destroy` before the sandbox expires,
  # or just let the sandbox reap everything.
  #
  # PRODUCTION: remote backend with locking + encryption + versioning.
  # And note: modules give you code REUSE; state SEPARATION in prod comes from
  # multiple root configs (e.g. envs/dev, envs/prod) each calling these modules
  # with their own backend key.
  #
  # backend "azurerm" { ... key = "aks-gitops.tfstate" }
}

provider "azurerm" {
  features {}

  # Sandbox identity — filled from terraform.tfvars (not env vars), so the
  # exact sandbox you're targeting is explicit and reviewable.
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  # The sandbox role (Starkiller) denies `*/register/action`, so azurerm's
  # default auto-registration of resource providers 403s on unrelated RPs.
  # Everything we need is already Registered, so skip registration entirely.
  # (azurerm 4.x replacement for the old 3.x `skip_provider_registration = true`.)
  resource_provider_registrations = "none"
}
