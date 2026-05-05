#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-private-endpoints.sh
# Create private endpoints + DNS zones for SQL, Storage, and Key Vault
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Private Endpoints Provisioning ==="

# --- Prerequisites ---
if ! check_prerequisites; then
    exit 1
fi

# =========================================================================
# Helper: create a private endpoint + private DNS zone + link + zone group
# =========================================================================
create_private_endpoint() {
    local pe_name="$1"
    local resource_id="$2"
    local group_id="$3"        # sub-resource: sqlServer, blob, vault
    local dns_zone="$4"        # e.g. privatelink.database.windows.net

    local dns_zone_name="${dns_zone}"
    local dns_link_name="link-${dns_zone//\./-}"  # dots to dashes for link name
    local zone_group_name="default"

    # --- Private Endpoint ---
    EXISTING_PE=$(az network private-endpoint show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$pe_name" \
        --query "name" \
        --output tsv 2>/dev/null)

    if [[ -n "$EXISTING_PE" ]]; then
        log_info "Private endpoint $pe_name already exists — skipping"
    else
        log_info "Creating private endpoint: $pe_name → $group_id"
        az network private-endpoint create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$pe_name" \
            --vnet-name "$VNET_NAME" \
            --subnet "$SNET_PE_NAME" \
            --private-connection-resource-id "$resource_id" \
            --group-id "$group_id" \
            --connection-name "${pe_name}-conn" \
            --location "$AZURE_LOCATION" \
            --tags $TAGS \
            --output none

        log_success "Private endpoint created: $pe_name"
    fi

    # --- Private DNS Zone ---
    EXISTING_ZONE=$(az network private-dns zone show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dns_zone_name" \
        --query "name" \
        --output tsv 2>/dev/null)

    if [[ -n "$EXISTING_ZONE" ]]; then
        log_info "DNS zone $dns_zone_name already exists — skipping"
    else
        log_info "Creating private DNS zone: $dns_zone_name"
        az network private-dns zone create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dns_zone_name" \
            --tags $TAGS \
            --output none

        log_success "DNS zone created: $dns_zone_name"
    fi

    # --- Link DNS zone to VNet ---
    EXISTING_LINK=$(az network private-dns link vnet show \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$dns_zone_name" \
        --name "$dns_link_name" \
        --query "name" \
        --output tsv 2>/dev/null)

    if [[ -n "$EXISTING_LINK" ]]; then
        log_info "DNS link $dns_link_name already exists — skipping"
    else
        log_info "Linking DNS zone to VNet..."
        az network private-dns link vnet create \
            --resource-group "$RESOURCE_GROUP" \
            --zone-name "$dns_zone_name" \
            --name "$dns_link_name" \
            --virtual-network "$VNET_NAME" \
            --registration-enabled false \
            --output none

        log_success "DNS zone linked to VNet"
    fi

    # --- DNS zone group (auto-registers A records) ---
    EXISTING_ZG=$(az network private-endpoint dns-zone-group show \
        --resource-group "$RESOURCE_GROUP" \
        --endpoint-name "$pe_name" \
        --name "$zone_group_name" \
        --query "name" \
        --output tsv 2>/dev/null)

    if [[ -n "$EXISTING_ZG" ]]; then
        log_info "DNS zone group already exists — skipping"
    else
        log_info "Creating DNS zone group for auto-registration..."
        az network private-endpoint dns-zone-group create \
            --resource-group "$RESOURCE_GROUP" \
            --endpoint-name "$pe_name" \
            --name "$zone_group_name" \
            --private-dns-zone "$dns_zone_name" \
            --zone-name "$group_id" \
            --output none

        log_success "DNS zone group created — A records auto-registered"
    fi

    echo ""
}

# =========================================================================
# Get resource IDs
# =========================================================================

# SQL Server
SQL_RESOURCE_ID=$(az sql server show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --query "id" \
    --output tsv 2>/dev/null)

if [[ -z "$SQL_RESOURCE_ID" ]]; then
    log_warn "SQL Server $SQL_SERVER_NAME not found — skipping SQL private endpoint (deploy issue #5 first)"
else
    log_info "--- SQL Server Private Endpoint ---"
    create_private_endpoint \
        "$PE_SQL_NAME" \
        "$SQL_RESOURCE_ID" \
        "sqlServer" \
        "privatelink.database.windows.net"
fi

# Storage Account
SA_RESOURCE_ID=$(az storage account show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query "id" \
    --output tsv 2>/dev/null)

if [[ -z "$SA_RESOURCE_ID" ]]; then
    log_warn "Storage account $STORAGE_ACCOUNT_NAME not found — skipping Storage private endpoint (deploy issue #6 first)"
else
    log_info "--- Storage Account Private Endpoint ---"
    create_private_endpoint \
        "$PE_STORAGE_NAME" \
        "$SA_RESOURCE_ID" \
        "blob" \
        "privatelink.blob.core.windows.net"
fi

# Key Vault
KV_RESOURCE_ID=$(az keyvault show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEYVAULT_NAME" \
    --query "id" \
    --output tsv 2>/dev/null)

if [[ -z "$KV_RESOURCE_ID" ]]; then
    log_warn "Key Vault $KEYVAULT_NAME not found — skipping Key Vault private endpoint (deploy issue #6 first)"
else
    log_info "--- Key Vault Private Endpoint ---"
    create_private_endpoint \
        "$PE_KV_NAME" \
        "$KV_RESOURCE_ID" \
        "vault" \
        "privatelink.vaultcore.azure.net"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
log_success "=== Private Endpoints Provisioning Complete ==="
echo ""

log_info "Private endpoints in $SNET_PE_NAME:"
az network private-endpoint list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, SubResource:privateLinkServiceConnections[0].groupIds[0]}" \
    --output table 2>/dev/null

echo ""
log_info "Private DNS zones:"
az network private-dns zone list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Zone:name, Records:numberOfRecordSets}" \
    --output table 2>/dev/null

echo ""
log_info "Services are now reachable from:"
echo "  - App Service (via VNet integration + snet-app)"
echo "  - Tailscale clients (via subnet router + snet-ts)"
echo ""
log_info "Test connectivity from your Mac (with Tailscale connected):"
echo "  nslookup ${SQL_SERVER_NAME}.database.windows.net"
echo "  nslookup ${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
echo "  nslookup ${KEYVAULT_NAME}.vault.azure.net"
echo ""
