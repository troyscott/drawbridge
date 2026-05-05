#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-monitoring.sh
# Create Log Analytics workspace and Application Insights
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Monitoring Provisioning ==="

if ! check_prerequisites; then
    exit 1
fi

# --- Log Analytics Workspace ---
EXISTING_LAW=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_LAW" ]]; then
    log_info "Log Analytics workspace $LOG_ANALYTICS_NAME already exists — skipping"
else
    log_info "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$AZURE_LOCATION" \
        --retention-time 30 \
        --tags $TAGS \
        --output none

    log_success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
fi

# Get workspace ID for App Insights
LAW_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query "id" \
    --output tsv 2>/dev/null)

# --- Application Insights (workspace-based) ---
EXISTING_APPI=$(az monitor app-insights component show \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APPINSIGHTS_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_APPI" ]]; then
    log_info "Application Insights $APPINSIGHTS_NAME already exists — skipping"
else
    log_info "Creating Application Insights: $APPINSIGHTS_NAME (workspace-based)"
    az monitor app-insights component create \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPINSIGHTS_NAME" \
        --location "$AZURE_LOCATION" \
        --kind web \
        --application-type web \
        --workspace "$LAW_ID" \
        --tags $TAGS \
        --output none

    log_success "Application Insights created: $APPINSIGHTS_NAME"
fi

# --- Get connection string ---
APPI_CONN_STRING=$(az monitor app-insights component show \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APPINSIGHTS_NAME" \
    --query "connectionString" \
    --output tsv 2>/dev/null)

# --- Set connection string on App Service (if it exists) ---
if az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Setting APPLICATIONINSIGHTS_CONNECTION_STRING on App Service..."
    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPI_CONN_STRING" \
        --output none

    log_success "App Insights connection string set on $APP_NAME"
else
    log_warn "App Service $APP_NAME not found — set the connection string after deploying it"
fi

# --- Summary ---
echo ""
log_success "=== Monitoring Provisioning Complete ==="
echo ""
echo "  Log Analytics: $LOG_ANALYTICS_NAME (30-day retention)"
echo "  App Insights:  $APPINSIGHTS_NAME (workspace-based)"
echo ""
