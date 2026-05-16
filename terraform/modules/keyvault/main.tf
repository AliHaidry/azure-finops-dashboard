resource "azurerm_key_vault" "main" {
  name                        = "finops-kv-${var.environment}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false   # set true for production

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = var.tags
}

# Store PostgreSQL connection string as a secret
resource "azurerm_key_vault_secret" "pg_connection_string" {
  name         = "pg-connection-string"
  value        = var.pg_connection_string
  key_vault_id = azurerm_key_vault.main.id

  tags = var.tags
}

# Placeholder for dashboard API key — set manually after first deploy
resource "azurerm_key_vault_secret" "dashboard_api_key" {
  name         = "dashboard-api-key"
  value        = "change-me-after-deploy"   # update via: az keyvault secret set
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]   # don't overwrite manual updates
  }
}
