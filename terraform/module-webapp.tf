resource "azurerm_service_plan" "main" {
  name                = "finops-asp-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  tags = var.tags
}

resource "azurerm_linux_web_app" "main" {
  name                = "finops-dashboard-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on        = false   # set true for production
    http2_enabled    = true
    ftps_state       = "Disabled"

    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    # Next.js runtime
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "NODE_ENV"                            = "production"
    "NEXTAUTH_URL"                        = "https://finops-dashboard-${var.environment}.azurewebsites.net"

    # Secrets fetched from Key Vault at runtime
    "DATABASE_URL"    = "@Microsoft.KeyVault(VaultName=finops-kv-${var.environment};SecretName=pg-connection-string)"
    "API_KEY"         = "@Microsoft.KeyVault(VaultName=finops-kv-${var.environment};SecretName=dashboard-api-key)"
    "KEY_VAULT_URI"   = var.key_vault_uri

    # Generated at deploy time
    "NEXTAUTH_SECRET" = random_password.nextauth_secret.result
  }

  logs {
    http_logs {
      retention_in_days = 7
    }
    application_logs {
      file_system_level = "Warning"
    }
  }

  tags = var.tags
}

# Key Vault access policy for the App Service managed identity
resource "azurerm_key_vault_access_policy" "webapp" {
  key_vault_id = data.azurerm_key_vault.main.id
  tenant_id    = azurerm_linux_web_app.main.identity[0].tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

data "azurerm_key_vault" "main" {
  name                = "finops-kv-${var.environment}"
  resource_group_name = var.resource_group_name
}

resource "random_password" "nextauth_secret" {
  length  = 32
  special = false
}

variable "resource_group_name"  { type = string }
variable "location"             { type = string }
variable "environment"          { type = string }
variable "sku_name"             { type = string }
variable "key_vault_uri"        { type = string }
variable "pg_connection_string" { type = string; sensitive = true }
variable "tags"                 { type = map(string) }

output "app_url" {
  value = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "app_service_id" {
  value = azurerm_linux_web_app.main.id
}

output "managed_identity_principal_id" {
  value = azurerm_linux_web_app.main.identity[0].principal_id
}
