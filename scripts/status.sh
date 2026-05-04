#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/status.sh
# Show status of all Azure resources
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🏰 Drawbridge — Status               ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

print_config

# --- Check resource group ---
if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Environment not deployed."
    exit 0
fi
log_success "Resource Group: $RESOURCE_GROUP exists"

# --- List resources ---
log_info "Resources in $RESOURCE_GROUP:"
echo ""
az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Type:type, Location:location}" \
    --output table 2>/dev/null

# --- App Service URL ---
APP_URL=$(az webapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "defaultHostName" \
    --output tsv 2>/dev/null)

if [[ -n "$APP_URL" ]]; then
    echo ""
    log_success "App Service URL: https://$APP_URL"
fi

# --- Tailscale VM ---
TS_STATUS=$(az vm show \
    --name "$TS_VM_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --show-details \
    --query "powerState" \
    --output tsv 2>/dev/null)

if [[ -n "$TS_STATUS" ]]; then
    log_info "Tailscale VM: $TS_VM_NAME — $TS_STATUS"
fi

echo ""
