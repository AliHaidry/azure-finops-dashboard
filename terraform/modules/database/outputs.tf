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
