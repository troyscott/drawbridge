#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-network.sh
# Create Resource Group, VNet, and subnets
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Network Provisioning ==="

# --- Prerequisites ---
if ! check_prerequisites; then
    exit 1
fi

# --- Resource Group ---
log_info "Creating resource group: $RESOURCE_GROUP"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$AZURE_LOCATION" \
    --tags $TAGS \
    --output none

log_success "Resource group: $RESOURCE_GROUP"

# --- VNet ---
log_info "Creating VNet: $VNET_NAME ($VNET_CIDR)"

# Check if VNet already exists
EXISTING_VNET=$(az network vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_VNET" ]]; then
    log_info "VNet $VNET_NAME already exists — skipping creation"
else
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_CIDR" \
        --location "$AZURE_LOCATION" \
        --tags $TAGS \
        --output none

    log_success "VNet created: $VNET_NAME"
fi

# --- Subnets ---
# Helper: create subnet if it doesn't exist
create_subnet() {
    local name="$1"
    local cidr="$2"
    local extra_args=("${@:3}")  # additional args (e.g. delegations)

    EXISTING=$(az network vnet subnet show \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$name" \
        --query "name" \
        --output tsv 2>/dev/null)

    if [[ -n "$EXISTING" ]]; then
        log_info "Subnet $name already exists — skipping"
    else
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$name" \
            --address-prefix "$cidr" \
            "${extra_args[@]}" \
            --output none

        log_success "Subnet created: $name ($cidr)"
    fi
}

# snet-app: App Service VNet integration (requires delegation)
log_info "Creating subnet: $SNET_APP_NAME ($SNET_APP_CIDR) — App Service integration"
create_subnet "$SNET_APP_NAME" "$SNET_APP_CIDR" \
    --delegations "Microsoft.Web/serverFarms"

# snet-pe: Private endpoints
log_info "Creating subnet: $SNET_PE_NAME ($SNET_PE_CIDR) — Private endpoints"
create_subnet "$SNET_PE_NAME" "$SNET_PE_CIDR"

# Disable private endpoint network policies on PE subnet (required for private endpoints)
az network vnet subnet update \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$SNET_PE_NAME" \
    --private-endpoint-network-policies Disabled \
    --output none 2>/dev/null

# snet-ts: Tailscale subnet router
log_info "Creating subnet: $SNET_TS_NAME ($SNET_TS_CIDR) — Tailscale subnet router"
create_subnet "$SNET_TS_NAME" "$SNET_TS_CIDR"

# --- Summary ---
echo ""
log_success "=== Network Provisioning Complete ==="
echo ""
log_info "VNet: $VNET_NAME ($VNET_CIDR)"
az network vnet subnet list \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --query "[].{Name:name, CIDR:addressPrefix, Delegations:delegations[0].serviceName}" \
    --output table 2>/dev/null
echo ""
