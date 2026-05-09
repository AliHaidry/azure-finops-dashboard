output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "pg_server_fqdn" {
  description = "PostgreSQL server fully-qualified domain name"
  value       = module.database.server_fqdn
}

output "pg_connection_string" {
  description = "PostgreSQL connection string (sensitive)"
  value       = module.database.connection_string
  sensitive   = true
}

output "key_vault_uri" {
  description = "Azure Key Vault URI"
  value       = module.keyvault.vault_uri
}

output "app_service_url" {
  description = "Next.js dashboard URL"
  value       = module.webapp.app_url
}

output "acr_login_server" {
  description = "Azure Container Registry login server — add as GitHub secret ACR_LOGIN_SERVER"
  value       = module.registry.login_server
}

output "acr_name" {
  description = "Azure Container Registry name — add as GitHub secret ACR_NAME"
  value       = module.registry.acr_name
}

output "github_actions_client_id" {
  description = "Client ID for GitHub Actions OIDC — add as GitHub secret AZURE_CLIENT_ID"
  value       = module.oidc.github_client_id
}

output "tenant_id" {
  description = "Azure AD tenant ID — add as GitHub secret AZURE_TENANT_ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "collector_principal_id" {
  description = "Service principal ID for the cost collector"
  value       = module.oidc.collector_principal_id
}

output "github_secrets_summary" {
  description = "Summary of all GitHub secrets to configure"
  value = <<-EOT
    ┌─────────────────────────────────────────────────────────────────┐
    │  GitHub Secrets to configure in your repository                  │
    │  Settings → Secrets and variables → Actions → New secret         │
    ├─────────────────────────────────────┬───────────────────────────┤
    │  AZURE_CLIENT_ID                    │  ${module.oidc.github_client_id}  │
    │  AZURE_TENANT_ID                    │  ${data.azurerm_client_config.current.tenant_id}  │
    │  AZURE_SUBSCRIPTION_ID              │  (your primary sub ID)    │
    │  ACR_LOGIN_SERVER                   │  ${module.registry.login_server}  │
    │  ACR_NAME                           │  ${module.registry.acr_name}  │
    └─────────────────────────────────────┴───────────────────────────┘
  EOT
}
