#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/status.sh
# Show status of the App Service environment.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   🏰 simple-app-easyauth — Status         ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

print_config

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Environment not deployed."
    exit 0
fi
log_success "Resource Group: $RESOURCE_GROUP exists"

log_info "Resources in $RESOURCE_GROUP:"
echo ""
az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Type:type, Location:location}" \
    --output table 2>/dev/null

APP_URL=$(az webapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "defaultHostName" \
    --output tsv 2>/dev/null)

if [[ -n "$APP_URL" ]]; then
    echo ""
    log_success "App Service URL: https://$APP_URL"
fi

echo ""
