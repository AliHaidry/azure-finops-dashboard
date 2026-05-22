# terraform.tfvars
subscription_ids = [
  "24838f8a-cebe-4693-81d3-26d6b74b47cd",  # Azure subscription dev
  "dd844520-0912-4407-b70b-53e40e499dfb",  # Azure subscription infra
  "f99345eb-69a8-455e-82d7-25706b78ccaf",  # Azure subscription poc
  "5e1b8934-9a3f-4464-9089-2e7af92fa160",  # Azure subscription app
]

location    = "eastus2"
environment = "dev"
github_org  = "AliHaidry"
github_repo = "azure-finops-dashboard"

pg_admin_username = "finops_admin"
pg_sku_name       = "B_Standard_B1ms"
pg_storage_mb     = 32768
pg_version        = "16"

app_service_sku   = "B1"

tags = {
  project = "azure-finops-dashboard"
  owner   = "ali.haidry"
}