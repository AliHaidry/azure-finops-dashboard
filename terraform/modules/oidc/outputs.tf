output "github_client_id" {
  description = "Client ID for GitHub Actions OIDC — add as AZURE_CLIENT_ID secret"
  value       = azuread_application.github_actions.client_id
}

output "collector_principal_id" {
  description = "Object ID of the collector service principal — used for Cost Management Reader role"
  value       = azuread_service_principal.collector.object_id
}

output "collector_client_id" {
  description = "Client ID for the cost collector service principal"
  value       = azuread_application.collector.client_id
}
