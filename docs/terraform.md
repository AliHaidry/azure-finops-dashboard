# Terraform Reference

All Azure infrastructure is provisioned via Terraform. No manual Azure Portal clicks required.

---

## What gets created

| Resource | Name pattern | Purpose |
|---|---|---|
| Resource Group | `finops-rg-{env}` | Logical container for all resources |
| PostgreSQL Flexible Server | `finops-pg-{env}` | Cost history database |
| PostgreSQL Database | `finops_db` | Application database |
| App Service Plan | `finops-asp-{env}` | Compute for Next.js app |
| App Service | `finops-dashboard-{env}` | Next.js stakeholder dashboard |
| Key Vault | `finops-kv-{env}` | Secrets storage |
| Container Registry | `finopsacr{env}` | Collector Docker image |
| App Registration | `finops-github-actions` | OIDC identity for GitHub Actions |
| Federated Credential | — | GitHub → Azure keyless auth |
| Role Assignment (ACR) | — | GitHub Actions can push to ACR |
| Role Assignment (Cost) | — | Collector can read Cost Management API |
| Role Assignment (KV) | — | App can read Key Vault secrets |

---

## File structure

```
terraform/
├── main.tf                 ← Provider configuration
├── variables.tf            ← Input variable declarations
├── terraform.tfvars.example ← Example values (copy to terraform.tfvars)
├── outputs.tf              ← Output values
├── modules/
│   ├── database/           ← PostgreSQL module
│   ├── webapp/             ← App Service module
│   ├── keyvault/           ← Key Vault module
│   └── oidc/               ← GitHub OIDC federation module
└── README.md               ← Module-level README
```

---

## Variables reference

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `subscription_ids` | list(string) | ✅ | — | Azure subscription IDs to monitor |
| `location` | string | — | `eastus2` | Azure region |
| `environment` | string | — | `dev` | Environment name (dev, staging, prod) |
| `github_org` | string | ✅ | — | GitHub organisation for OIDC trust |
| `github_repo` | string | ✅ | — | GitHub repository name |
| `pg_admin_username` | string | — | `finops_admin` | PostgreSQL admin username |
| `pg_sku_name` | string | — | `B_Standard_B1ms` | PostgreSQL compute tier |
| `pg_storage_mb` | number | — | `32768` | PostgreSQL storage (MB) |
| `pg_version` | string | — | `16` | PostgreSQL major version |
| `app_service_sku` | string | — | `B1` | App Service plan SKU |
| `key_vault_sku` | string | — | `standard` | Key Vault pricing tier |
| `tags` | map(string) | — | `{}` | Additional Azure resource tags |

---

## Outputs reference

| Output | Description | Used by |
|---|---|---|
| `pg_connection_string` | PostgreSQL connection string | Collector, Next.js app |
| `pg_server_fqdn` | PostgreSQL server hostname | Direct DB access |
| `app_service_url` | Next.js dashboard URL | Testing, docs |
| `key_vault_uri` | Key Vault URI | App configuration |
| `acr_login_server` | Container registry hostname | GitHub Actions |
| `acr_name` | Container registry name | GitHub Actions |
| `github_actions_client_id` | OIDC client ID | GitHub Actions secret |
| `tenant_id` | Azure AD tenant ID | GitHub Actions secret |
| `collector_managed_identity_id` | Managed identity for collector | Collector auth |

---

## Terraform commands reference

```bash
# Initialise (download providers)
terraform init

# Preview changes
terraform plan -var="subscription_ids=[\"sub-a\",\"sub-b\",\"sub-c\"]"

# Apply (create resources)
terraform apply

# Apply with var file
terraform apply -var-file="terraform.tfvars"

# Destroy all resources (careful!)
terraform destroy

# Show current state
terraform show

# List all resources in state
terraform state list

# Import an existing resource
terraform import azurerm_resource_group.main /subscriptions/{id}/resourceGroups/finops-rg-dev
```

---

## Adding a new subscription

1. Add the subscription ID to `terraform.tfvars`:

```hcl
subscription_ids = [
  "existing-sub-a",
  "existing-sub-b",
  "new-sub-d"          # ← add here
]
```

2. Apply:

```bash
terraform apply
# Terraform will add the new Cost Management Reader role assignment
```

3. Update the collector `.env`:

```bash
SUBSCRIPTION_IDS=existing-sub-a,existing-sub-b,new-sub-d
```

4. Run a backfill for the new subscription:

```bash
python collector.py --subscription new-sub-d --backfill 30
```

---

## Cost of this infrastructure

Approximate monthly cost on Azure (dev tier):

| Resource | SKU | Approx. cost/month |
|---|---|---|
| PostgreSQL Flexible Server | B_Standard_B1ms | ~$13 |
| App Service | B1 | ~$13 |
| Key Vault | Standard | ~$0.03 |
| Container Registry | Basic | ~$5 |
| Storage (logs, state) | LRS | ~$1 |
| **Total** | | **~$32/month** |

> Run `terraform destroy` when not actively developing to avoid charges.
> The Terraform state is stored locally by default — for team use, configure a remote backend (Azure Storage).

---

## Remote state (recommended for teams)

```hcl
# terraform/main.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatefinops"
    container_name       = "tfstate"
    key                  = "finops-dashboard.tfstate"
  }
}
```

Create the storage account first:
```bash
az group create --name terraform-state-rg --location eastus2
az storage account create --name tfstatefinops --resource-group terraform-state-rg --sku Standard_LRS
az storage container create --name tfstate --account-name tfstatefinops
```
