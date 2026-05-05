#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-monitoring.sh
# Remove Application Insights and Log Analytics workspace
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Monitoring Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Delete Application Insights first ---
if az monitor app-insights component show \
    --resource-group "$RESOURCE_GROUP" \
    --app "$APPINSIGHTS_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting Application Insights: $APPINSIGHTS_NAME"
    az monitor app-insights component delete \
        --resource-group "$RESOURCE_GROUP" \
        --app "$APPINSIGHTS_NAME" \
        --output none
    log_success "Deleted: $APPINSIGHTS_NAME"
else
    log_info "Application Insights $APPINSIGHTS_NAME not found — skipping"
fi

# --- Delete Log Analytics workspace ---
if az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting Log Analytics workspace: $LOG_ANALYTICS_NAME"
    az monitor log-analytics workspace delete \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --yes \
        --force \
        --output none
    log_success "Deleted: $LOG_ANALYTICS_NAME"
else
    log_info "Log Analytics workspace $LOG_ANALYTICS_NAME not found — skipping"
fi

echo ""
log_success "=== Monitoring Teardown Complete ==="
echo ""
