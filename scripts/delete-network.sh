#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-network.sh
# Delete VNet, subnets, and (optionally) the resource group
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Network Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

# --- Check if resource group exists ---
if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Delete subnets (reverse order) ---
delete_subnet() {
    local name="$1"
    if az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$name" \
        --query "name" \
        --output tsv &>/dev/null; then

        log_info "Deleting subnet: $name"
        az network vnet subnet delete \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$name" \
            --output none 2>/dev/null
        log_success "Deleted subnet: $name"
    else
        log_info "Subnet $name not found — skipping"
    fi
}

delete_subnet "$SNET_TS_NAME"
delete_subnet "$SNET_PE_NAME"
delete_subnet "$SNET_APP_NAME"

# --- Delete VNet ---
if az network vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting VNet: $VNET_NAME"
    az network vnet delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --output none
    log_success "Deleted VNet: $VNET_NAME"
else
    log_info "VNet $VNET_NAME not found — skipping"
fi

# --- Optionally delete resource group ---
if [[ "$1" == "--include-rg" ]]; then
    log_info "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
else
    log_info "Resource group $RESOURCE_GROUP preserved. Pass --include-rg to delete it."
fi

echo ""
log_success "=== Network Teardown Complete ==="
echo ""
