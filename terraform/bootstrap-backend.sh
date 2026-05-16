#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap-backend.sh
# Run this ONCE before terraform init to create the Azure Storage backend
# for Terraform remote state.
#
# Usage:
#   chmod +x bootstrap-backend.sh
#   ./bootstrap-backend.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="finops-tfstate-rg"
STORAGE_ACCOUNT="finopstfstateali"     # must be globally unique — change if taken
CONTAINER_NAME="tfstate"
LOCATION="eastus2"

echo "──────────────────────────────────────────"
echo "  FinOps Dashboard — Terraform Backend Setup"
echo "──────────────────────────────────────────"
echo ""

# 1. Login check
echo "→ Checking Azure login..."
az account show --query name -o tsv || { echo "Run 'az login' first"; exit 1; }
echo ""

# 2. Create resource group for Terraform state
echo "→ Creating resource group: $RESOURCE_GROUP"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
echo "  ✓ Resource group created"

# 3. Create storage account
echo "→ Creating storage account: $STORAGE_ACCOUNT"
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none
echo "  ✓ Storage account created"

# 4. Enable versioning (protects state files)
echo "→ Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --enable-versioning true \
  --output none
echo "  ✓ Blob versioning enabled"

# 5. Create container
echo "→ Creating blob container: $CONTAINER_NAME"
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --output none
echo "  ✓ Container created"

echo ""
echo "──────────────────────────────────────────"
echo "  Backend ready. Now run:"
echo ""
echo "  cd terraform"
echo "  cp terraform.tfvars.example terraform.tfvars"
echo "  # Edit terraform.tfvars with your values"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
echo "──────────────────────────────────────────"
