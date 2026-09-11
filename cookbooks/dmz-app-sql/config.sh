#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/dmz-app-sql/config.sh
# Config for the "dmz-app-sql" cookbook: public App Service (VNet-integrated,
# Entra Easy Auth) with SQL/Storage/Key Vault behind private endpoints and a
# Tailscale subnet router for private dev access.
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
PROJECT="drawbridge-dmz"
ENV="${ENV:-dev}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"

# --- Azure subscription ---
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"

# --- Resource names: {resource}-{project}-{env} ---
RESOURCE_GROUP="rg-${PROJECT}-${ENV}-${AZURE_LOCATION}"
VNET_NAME="vnet-${PROJECT}-${ENV}"
VNET_CIDR="10.50.0.0/24"

# Subnets
SNET_APP_NAME="snet-app"
SNET_APP_CIDR="10.50.0.0/26"
SNET_PE_NAME="snet-pe"
SNET_PE_CIDR="10.50.0.64/26"
SNET_TS_NAME="snet-ts"
SNET_TS_CIDR="10.50.0.128/26"

# App Service
ASP_NAME="asp-${PROJECT}-${ENV}"
APP_NAME="app-${PROJECT}-${ENV}"
ASP_SKU="${ASP_SKU:-B1}"

# Azure SQL
SQL_SERVER_NAME="sql-${PROJECT}-${ENV}"
SQL_DB_NAME="sqldb-${PROJECT}-${ENV}"
SQL_DB_SKU="${SQL_DB_SKU:-GP_S_Gen5_2}"       # Serverless Gen5 2vCore
SQL_DB_AUTOPAUSE="${SQL_DB_AUTOPAUSE:-60}"     # minutes

# Storage
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(echo "$AZURE_SUBSCRIPTION_ID" | md5sum 2>/dev/null | cut -c1-6 || echo "000000")}"
STORAGE_ACCOUNT_NAME="st${PROJECT//-/}${ENV}${RANDOM_SUFFIX}"
STORAGE_SKU="${STORAGE_SKU:-Standard_LRS}"

# Key Vault
KEYVAULT_NAME="kv-${PROJECT}-${ENV}-${RANDOM_SUFFIX}"

# Private Endpoints
PE_SQL_NAME="pe-sql-${PROJECT}-${ENV}"
PE_STORAGE_NAME="pe-st-${PROJECT}-${ENV}"
PE_KV_NAME="pe-kv-${PROJECT}-${ENV}"

# Monitoring
LOG_ANALYTICS_NAME="law-${PROJECT}-${ENV}"
APPINSIGHTS_NAME="appi-${PROJECT}-${ENV}"

# Tailscale subnet router VM
TS_VM_NAME="vm-${PROJECT}-ts-${ENV}"
TS_VM_SIZE="${TS_VM_SIZE:-Standard_B1s}"
TS_VM_IMAGE="${TS_VM_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"

# Tailscale auth key (from .env, never hardcoded)
TS_AUTHKEY="${TS_AUTHKEY:-}"

# --- Tags applied to all resources ---
TAGS="project=${PROJECT} environment=${ENV} managedBy=drawbridge cookbook=dmz-app-sql"

# Print a summary of all configured resource names
print_config() {
    echo ""
    log_info "=== dmz-app-sql Configuration ==="
    echo "  Project:        $PROJECT"
    echo "  Environment:    $ENV"
    echo "  Location:       $AZURE_LOCATION"
    echo "  Subscription:   $AZURE_SUBSCRIPTION_ID"
    echo ""
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  VNet:           $VNET_NAME ($VNET_CIDR)"
    echo "  App Service:    $APP_NAME (Plan: $ASP_NAME, SKU: $ASP_SKU)"
    echo "  SQL Server:     $SQL_SERVER_NAME"
    echo "  SQL Database:   $SQL_DB_NAME"
    echo "  Storage:        $STORAGE_ACCOUNT_NAME"
    echo "  Key Vault:      $KEYVAULT_NAME"
    echo "  Tailscale VM:   $TS_VM_NAME ($TS_VM_SIZE)"
    echo "  App Insights:   $APPINSIGHTS_NAME"
    echo ""
}
