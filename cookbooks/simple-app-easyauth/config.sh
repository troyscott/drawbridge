#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/config.sh
# Config for the "simple-app-easyauth" cookbook: a bare App Service with
# Entra ID (Easy Auth v2) authentication. No VNet, no private backend —
# the minimal end of the spectrum for quick POCs.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_ROOT/lib/common.sh"

# --- Load .env if present (secrets, shared overrides) ---
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
fi

# --- Project defaults ---
# PROJECT is fixed per cookbook (not overridable via the shared .env) so two
# cookbooks never collide on the same resource names when both are deployed.
PROJECT="drawbridge-simple"
ENV="${ENV:-dev}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"

# --- Azure subscription ---
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"

# --- Resource names: {resource}-{project}-{env} ---
RESOURCE_GROUP="rg-${PROJECT}-${ENV}-${AZURE_LOCATION}"

# App Service
ASP_NAME="asp-${PROJECT}-${ENV}"
APP_NAME="app-${PROJECT}-${ENV}"
ASP_SKU="${ASP_SKU:-B1}"

# --- Tags applied to all resources ---
TAGS="project=${PROJECT} environment=${ENV} managedBy=drawbridge cookbook=simple-app-easyauth"

# Print a summary of all configured resource names
print_config() {
    echo ""
    log_info "=== simple-app-easyauth Configuration ==="
    echo "  Project:        $PROJECT"
    echo "  Environment:    $ENV"
    echo "  Location:       $AZURE_LOCATION"
    echo "  Subscription:   $AZURE_SUBSCRIPTION_ID"
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  App Service:    $APP_NAME (Plan: $ASP_NAME, SKU: $ASP_SKU)"
    echo ""
}
