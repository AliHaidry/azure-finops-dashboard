# provider "azurerm" { alias = "app" ... } is declared in terraform-main.tf
# All resources below target the app subscription via provider = azurerm.app

resource "azurerm_resource_group" "app" {
  provider = azurerm.app
  name     = "finops-app-rg"
  location = "eastus2"
  tags     = local.common_tags
}

resource "azurerm_service_plan" "app" {
  provider            = azurerm.app
  name                = "finops-asp-app"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "app" {
  provider            = azurerm.app
  name                = "finops-dashboard-app"
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  service_plan_id     = azurerm_service_plan.app.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on     = false
    http2_enabled = true
    ftps_state    = "Disabled"
    application_stack {
      node_version = "20-lts"
    }
  }

  app_settings = {
    "NODE_ENV"        = "production"
    "NEXTAUTH_URL"    = "https://finops-dashboard-app.azurewebsites.net"
    "DATABASE_URL"    = "@Microsoft.KeyVault(VaultName=finopskvalidev;SecretName=pg-connection-string)"
    "NEXTAUTH_SECRET" = random_password.nextauth_secret_app.result
  }

  tags = local.common_tags
}

resource "random_password" "nextauth_secret_app" {
  length  = 32
  special = false
}

output "app_service_url" {
  value = "https://${azurerm_linux_web_app.app.default_hostname}"
}
