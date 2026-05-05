#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-private-endpoints.sh
# Remove private endpoints, DNS zone groups, DNS zones, and VNet links
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Private Endpoints Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# =========================================================================
# Helper: delete a private endpoint and its DNS zone + VNet link
# =========================================================================
delete_private_endpoint() {
    local pe_name="$1"
    local dns_zone="$2"
    local dns_link_name="link-${dns_zone//./-}"

    # Delete private endpoint (zone group is deleted automatically)
    if az network private-endpoint show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$pe_name" \
        --query "name" \
        --output tsv &>/dev/null; then

        log_info "Deleting private endpoint: $pe_name"
        az network private-endpoint delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pe_name" \
            --output none
        log_success "Deleted: $pe_name"
    else
        log_info "Private endpoint $pe_name not found — skipping"
    fi

    # Delete DNS VNet link
    if az network private-dns link vnet show \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$dns_zone" \
        --name "$dns_link_name" \
        --query "name" \
        --output tsv &>/dev/null; then

        log_info "Deleting DNS VNet link: $dns_link_name"
        az network private-dns link vnet delete \
            --resource-group "$RESOURCE_GROUP" \
            --zone-name "$dns_zone" \
            --name "$dns_link_name" \
            --yes \
            --output none
        log_success "Deleted DNS link: $dns_link_name"
    fi

    # Delete DNS zone
    if az network private-dns zone show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dns_zone" \
        --query "name" \
        --output tsv &>/dev/null; then

        log_info "Deleting DNS zone: $dns_zone"
        az network private-dns zone delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dns_zone" \
            --yes \
            --output none
        log_success "Deleted DNS zone: $dns_zone"
    fi

    echo ""
}

# --- Delete all three ---
log_info "--- SQL Private Endpoint ---"
delete_private_endpoint "$PE_SQL_NAME" "privatelink.database.windows.net"

log_info "--- Storage Private Endpoint ---"
delete_private_endpoint "$PE_STORAGE_NAME" "privatelink.blob.core.windows.net"

log_info "--- Key Vault Private Endpoint ---"
delete_private_endpoint "$PE_KV_NAME" "privatelink.vaultcore.azure.net"

echo ""
log_success "=== Private Endpoints Teardown Complete ==="
echo ""
