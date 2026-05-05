#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-storage.sh
# Remove Storage account and Key Vault
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Storage & Key Vault Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Delete Storage account ---
if az storage account show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting Storage account: $STORAGE_ACCOUNT_NAME"
    az storage account delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --yes \
        --output none
    log_success "Deleted Storage account: $STORAGE_ACCOUNT_NAME"
else
    log_info "Storage account $STORAGE_ACCOUNT_NAME not found — skipping"
fi

# --- Delete Key Vault ---
if az keyvault show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEYVAULT_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting Key Vault: $KEYVAULT_NAME"
    az keyvault delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KEYVAULT_NAME" \
        --output none
    log_success "Deleted Key Vault: $KEYVAULT_NAME"

    # Purge to allow re-creation with same name
    log_info "Purging soft-deleted Key Vault..."
    az keyvault purge \
        --name "$KEYVAULT_NAME" \
        --no-wait \
        --output none 2>/dev/null
    log_success "Key Vault purge initiated"
else
    log_info "Key Vault $KEYVAULT_NAME not found — skipping"
fi

echo ""
log_success "=== Storage & Key Vault Teardown Complete ==="
echo ""
