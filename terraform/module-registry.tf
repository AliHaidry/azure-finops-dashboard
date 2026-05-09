resource "azurerm_container_registry" "main" {
  # ACR names must be globally unique, alphanumeric only, 5-50 chars
  name                = "finopsacr${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false   # use OIDC instead of admin credentials

  tags = var.tags
}

variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "environment"         { type = string }
variable "tags"                { type = map(string) }

output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}
