# App registration for GitHub Actions — used by CI to push to ACR
resource "azuread_application" "github_actions" {
  display_name = "finops-github-actions"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# OIDC federation — GitHub Actions authenticates without stored secrets
resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main"
  description    = "GitHub Actions on main branch"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-pr"
  description    = "GitHub Actions on pull requests"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.github_repo}:pull_request"
}

# ACR Push — GitHub Actions can push collector Docker image
resource "azurerm_role_assignment" "github_acr_push" {
  scope                = var.acr_id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# Contributor on resource group — GitHub Actions can deploy to App Service
resource "azurerm_role_assignment" "github_rg_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# App registration for the cost collector — used by the Python script
resource "azuread_application" "collector" {
  display_name = "finops-cost-collector"
}

resource "azuread_service_principal" "collector" {
  client_id = azuread_application.collector.client_id
}

# Cost Management Reader on each subscription — set in main.tf via for_each
# The principal_id is exported as collector_principal_id

variable "github_org"        { type = string }
variable "github_repo"       { type = string }
variable "resource_group_id" { type = string }
variable "acr_id"            { type = string }
variable "subscription_ids"  { type = list(string) }

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
