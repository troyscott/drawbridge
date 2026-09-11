#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/delete-appservice.sh
# Remove App Service, App Service Plan, Entra app registration, and the
# resource group.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== App Service Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Delete Web App ---
if az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting Web App: $APP_NAME"
    az webapp delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --output none
    log_success "Deleted Web App: $APP_NAME"
else
    log_info "Web App $APP_NAME not found — skipping"
fi

# --- Delete App Service Plan ---
if az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ASP_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting App Service Plan: $ASP_NAME"
    az appservice plan delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ASP_NAME" \
        --yes \
        --output none
    log_success "Deleted App Service Plan: $ASP_NAME"
else
    log_info "App Service Plan $ASP_NAME not found — skipping"
fi

# --- Delete Entra app registration ---
ENTRA_APP_NAME="app-${PROJECT}-${ENV}-auth"
ENTRA_APP_ID=$(az ad app list \
    --display-name "$ENTRA_APP_NAME" \
    --query "[0].id" \
    --output tsv 2>/dev/null)

if [[ -n "$ENTRA_APP_ID" ]]; then
    log_info "Deleting Entra app registration: $ENTRA_APP_NAME"
    az ad app delete --id "$ENTRA_APP_ID" --output none 2>/dev/null
    log_success "Deleted Entra app registration"
else
    log_info "Entra app registration $ENTRA_APP_NAME not found — skipping"
fi

# --- Delete resource group ---
log_info "Deleting resource group: $RESOURCE_GROUP"
az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait \
    --output none
log_success "Resource group deletion initiated (running in background)"

echo ""
log_success "=== App Service Teardown Complete ==="
echo ""
