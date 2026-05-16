resource "azurerm_container_registry" "main" {
  # ACR names must be globally unique, alphanumeric only, 5-50 chars
  name                = "finopsacr${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false   # use OIDC instead of admin credentials

  tags = var.tags
}
