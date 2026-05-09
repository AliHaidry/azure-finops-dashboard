variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "environment"         { type = string }
variable "admin_username"      { type = string }
variable "sku_name"            { type = string }
variable "storage_mb"          { type = number }
variable "pg_version"          { type = string }
variable "tags"                { type = map(string) }

output "server_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "connection_string" {
  value     = "postgresql://${var.admin_username}:${random_password.pg_password.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/finops_db?sslmode=require"
  sensitive = true
}

output "server_name" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "pg_password" {
  value     = random_password.pg_password.result
  sensitive = true
}
