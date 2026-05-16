resource "random_password" "pg_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "finops-pg-${var.environment}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.pg_version
  administrator_login    = var.admin_username
  administrator_password = random_password.pg_password.result
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  backup_retention_days  = 7
  zone                   = "1"

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "finops" {
  name      = "finops_db"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# Allow Azure services to connect (for App Service and collector)
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Allow your local IP for development — update this to your actual IP
resource "azurerm_postgresql_flexible_server_firewall_rule" "local_dev" {
  name             = "AllowLocalDev"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"   # replace with your IP: curl ifconfig.me
  end_ip_address   = "0.0.0.0"   # replace with your IP
}

# PostgreSQL configuration — tuned for cost data workload
resource "azurerm_postgresql_flexible_server_configuration" "work_mem" {
  name      = "work_mem"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "16384"   # 16 MB — helps with aggregation queries
}

resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "50"
}
