# Identity module — the TARGET of Workload Identity federation.
#
# SANDBOX ADAPTATION: the doc uses Key Vault RBAC (`enable_rbac_authorization =
# true`) + an `azurerm_role_assignment` of "Key Vault Secrets User". This sandbox
# DENIES `Microsoft.Authorization/roleAssignments/write`, so we use the Key Vault
# ACCESS POLICY model instead (set via the vault resource itself, which we ARE
# allowed to write). The Workload Identity mechanism is unchanged — only the
# Key Vault authorization model differs. In production you'd prefer RBAC.

resource "random_string" "kv" {
  length  = 6
  upper   = false
  special = false
  numeric = true
}

resource "azurerm_key_vault" "this" {
  name                       = "${var.prefix}-kv-${random_string.kv.result}" # globally unique, 3-24 chars
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = false # SANDBOX: access policies, not RBAC (role assignments are denied)
  purge_protection_enabled   = false # lab only; turn on in prod
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# The pod's identity. user-assigned (system-assigned can't have federated creds).
resource "azurerm_user_assigned_identity" "kv_reader" {
  name                = "${var.prefix}-kv-reader-mi"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Access policy: let the deploying user manage secrets (so TF can write the demo
# secret and you can read it from the CLI for debugging).
resource "azurerm_key_vault_access_policy" "admin" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = var.admin_object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# Access policy: the managed identity gets READ on secrets — the "Key Vault
# Secrets User" equivalent, expressed as an access policy.
resource "azurerm_key_vault_access_policy" "kv_reader" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.kv_reader.principal_id

  secret_permissions = ["Get", "List"]
}

# The federated credential — THE Workload Identity link. Pins (issuer, subject)
# to the managed identity. Subject must equal the K8s SA exactly.
resource "azurerm_federated_identity_credential" "kv_reader" {
  name                = "${var.prefix}-kv-reader-fed"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.kv_reader.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.sa_namespace}:${var.sa_name}"
}

# The demo secret the pod will pull. Waits for the admin policy to exist.
resource "azurerm_key_vault_secret" "demo" {
  name         = var.secret_name
  value        = var.secret_value
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_key_vault_access_policy.admin]
}
