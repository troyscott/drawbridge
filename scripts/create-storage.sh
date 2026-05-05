#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-storage.sh
# Create Storage account (Blob, private) and Key Vault (RBAC, private)
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Storage & Key Vault Provisioning ==="

# --- Prerequisites ---
if ! check_prerequisites; then
    exit 1
fi

# =========================================================================
# Storage Account
# =========================================================================

EXISTING_SA=$(az storage account show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_SA" ]]; then
    log_info "Storage account $STORAGE_ACCOUNT_NAME already exists — skipping creation"
else
    log_info "Creating Storage account: $STORAGE_ACCOUNT_NAME ($STORAGE_SKU)"
    az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --location "$AZURE_LOCATION" \
        --sku "$STORAGE_SKU" \
        --kind StorageV2 \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --https-only true \
        --tags $TAGS \
        --output none

    log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
fi

# --- Disable public network access ---
log_info "Disabling public network access on Storage..."
az storage account update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --public-network-access Disabled \
    --output none 2>/dev/null

log_success "Storage public access disabled"

# --- Grant App Service MI: Storage Blob Data Contributor ---
MI_PRINCIPAL_ID=$(az webapp identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "principalId" \
    --output tsv 2>/dev/null)

if [[ -n "$MI_PRINCIPAL_ID" ]]; then
    SA_RESOURCE_ID=$(az storage account show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --query "id" \
        --output tsv 2>/dev/null)

    log_info "Granting App Service MI 'Storage Blob Data Contributor' role..."
    az role assignment create \
        --assignee-object-id "$MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Blob Data Contributor" \
        --scope "$SA_RESOURCE_ID" \
        --output none 2>/dev/null

    log_success "Role assigned to MI: Storage Blob Data Contributor"
else
    log_warn "App Service $APP_NAME not found — deploy it first to grant MI access"
fi

# =========================================================================
# Key Vault
# =========================================================================

EXISTING_KV=$(az keyvault show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEYVAULT_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_KV" ]]; then
    log_info "Key Vault $KEYVAULT_NAME already exists — skipping creation"
else
    # Check for soft-deleted vault with same name (blocks re-creation)
    SOFT_DELETED=$(az keyvault list-deleted \
        --query "[?name=='$KEYVAULT_NAME'].name" \
        --output tsv 2>/dev/null)

    if [[ -n "$SOFT_DELETED" ]]; then
        log_info "Purging soft-deleted Key Vault: $KEYVAULT_NAME"
        az keyvault purge --name "$KEYVAULT_NAME" --output none 2>/dev/null
        log_success "Purged soft-deleted vault"
    fi

    log_info "Creating Key Vault: $KEYVAULT_NAME (RBAC mode)"
    az keyvault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KEYVAULT_NAME" \
        --location "$AZURE_LOCATION" \
        --sku standard \
        --enable-rbac-authorization true \
        --retention-days 7 \
        --tags $TAGS \
        --output none

    log_success "Key Vault created: $KEYVAULT_NAME"
fi

# --- Disable public network access ---
log_info "Disabling public network access on Key Vault..."
az keyvault update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEYVAULT_NAME" \
    --public-network-access Disabled \
    --output none 2>/dev/null

log_success "Key Vault public access disabled"

# --- Grant App Service MI: Key Vault Secrets User ---
if [[ -n "$MI_PRINCIPAL_ID" ]]; then
    KV_RESOURCE_ID=$(az keyvault show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KEYVAULT_NAME" \
        --query "id" \
        --output tsv 2>/dev/null)

    log_info "Granting App Service MI 'Key Vault Secrets User' role..."
    az role assignment create \
        --assignee-object-id "$MI_PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Key Vault Secrets User" \
        --scope "$KV_RESOURCE_ID" \
        --output none 2>/dev/null

    log_success "Role assigned to MI: Key Vault Secrets User"
fi

# --- Grant current user: Key Vault Administrator (for managing secrets) ---
CURRENT_USER_ID=$(az ad signed-in-user show --query "id" --output tsv 2>/dev/null)

if [[ -n "$CURRENT_USER_ID" && -n "${KV_RESOURCE_ID:-}" ]]; then
    log_info "Granting current user 'Key Vault Administrator' role..."
    az role assignment create \
        --assignee-object-id "$CURRENT_USER_ID" \
        --assignee-principal-type User \
        --role "Key Vault Administrator" \
        --scope "$KV_RESOURCE_ID" \
        --output none 2>/dev/null

    log_success "Role assigned to current user: Key Vault Administrator"
fi

# --- Summary ---
echo ""
log_success "=== Storage & Key Vault Provisioning Complete ==="
echo ""
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Storage SKU:     $STORAGE_SKU"
echo "  Public access:   Disabled"
echo ""
echo "  Key Vault:       $KEYVAULT_NAME"
echo "  Mode:            RBAC authorization"
echo "  Retention:       7 days (soft-delete)"
echo "  Public access:   Disabled"
echo ""
if [[ -n "$MI_PRINCIPAL_ID" ]]; then
    echo "  MI Roles:"
    echo "    Storage: Blob Data Contributor"
    echo "    KV:      Key Vault Secrets User"
fi
echo ""
