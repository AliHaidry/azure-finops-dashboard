variable "subscription_ids" {
  description = "List of Azure subscription IDs to monitor for cost data"
  type        = list(string)

  validation {
    condition     = length(var.subscription_ids) >= 1
    error_message = "At least one subscription ID must be provided."
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name — used in resource naming (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "github_org" {
  description = "GitHub organisation name for OIDC federation"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for OIDC federation"
  type        = string
  default     = "azure-finops-dashboard"
}

variable "pg_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "finops_admin"
}

variable "pg_sku_name" {
  description = "PostgreSQL Flexible Server SKU — B_Standard_B1ms is cheapest for dev"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "pg_storage_mb" {
  description = "PostgreSQL storage in MB"
  type        = number
  default     = 32768   # 32 GB
}

variable "pg_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "app_service_sku" {
  description = "App Service plan SKU for the Next.js dashboard"
  type        = string
  default     = "B1"
}

variable "key_vault_sku" {
  description = "Azure Key Vault pricing tier"
  type        = string
  default     = "standard"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
