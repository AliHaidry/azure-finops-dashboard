terraform {
  required_version = ">= 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    resource_group_name  = "finops-tfstate-rg"
    storage_account_name = "finopstfstateali"       # must be globally unique — change if taken
    container_name       = "tfstate"
    key                  = "finops-dashboard.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

# ── Data sources ─────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# ── Resource Group ───────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "finops-rg-${var.environment}"
  location = var.location

  tags = merge(var.tags, {
    project     = "azure-finops-dashboard"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "ali.haidry"
  })
}

# ── Modules ──────────────────────────────────────────────────────────────────

module "database" {
  source = "./modules/database"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  admin_username      = var.pg_admin_username
  sku_name            = var.pg_sku_name
  storage_mb          = var.pg_storage_mb
  pg_version          = var.pg_version
  tags                = azurerm_resource_group.main.tags
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = data.azurerm_client_config.current.object_id
  pg_connection_string = module.database.connection_string
  tags                = azurerm_resource_group.main.tags
}

module "registry" {
  source = "./modules/registry"

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = var.environment
  tags                = azurerm_resource_group.main.tags
}

module "webapp" {
  source = "./modules/webapp"

  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  environment          = var.environment
  sku_name             = var.app_service_sku
  key_vault_uri        = module.keyvault.vault_uri
  pg_connection_string = module.database.connection_string
  tags                 = azurerm_resource_group.main.tags
}

module "oidc" {
  source = "./modules/oidc"

  github_org          = var.github_org
  github_repo         = var.github_repo
  resource_group_id   = azurerm_resource_group.main.id
  acr_id              = module.registry.acr_id
  subscription_ids    = var.subscription_ids
}

# ── Cost Management Reader — one role assignment per subscription ─────────────

resource "azurerm_role_assignment" "cost_reader" {
  for_each = toset(var.subscription_ids)

  scope                = "/subscriptions/${each.value}"
  role_definition_name = "Cost Management Reader"
  principal_id         = module.oidc.collector_principal_id
}
