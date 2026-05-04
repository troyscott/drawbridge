#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/config.sh
# Central configuration sourced by all infrastructure scripts.
# =============================================================================

# --- Load .env if present (secrets, overrides) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
fi

# --- Project defaults (override via .env) ---
PROJECT="${PROJECT:-drawbridge}"
ENV="${ENV:-dev}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"

# --- Azure subscription ---
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"

# --- Naming convention: {resource}-{project}-{env}-{region} ---
# Short region codes for resource naming
declare -A REGION_SHORT=(
    [eastus]="eus"
    [eastus2]="eus2"
    [westus]="wus"
    [westus2]="wus2"
    [centralus]="cus"
    [northeurope]="neu"
    [westeurope]="weu"
)
REGION_CODE="${REGION_SHORT[$AZURE_LOCATION]:-$AZURE_LOCATION}"

# --- Resource names ---
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
STORAGE_ACCOUNT_NAME="st${PROJECT}${ENV}${RANDOM_SUFFIX}"
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
TAGS="project=${PROJECT} environment=${ENV} managedBy=drawbridge"

# =============================================================================
# Helper functions
# =============================================================================

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $*"
}

log_success() {
    echo -e "\033[0;32m[OK]\033[0m $*"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

# Check that required CLI tools are available
check_prerequisites() {
    local missing=0
    for cmd in az jq; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        log_error "AZURE_SUBSCRIPTION_ID is not set. Add it to .env or export it."
        missing=1
    fi

    # Verify az login
    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        return 1
    fi

    # Set subscription
    az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null
    log_success "Using subscription: $(az account show --query name -o tsv)"
    return 0
}

# Check if a resource group exists
resource_group_exists() {
    az group exists --name "$RESOURCE_GROUP" 2>/dev/null | grep -q "true"
}

# Print a summary of all configured resource names
print_config() {
    echo ""
    log_info "=== Drawbridge Configuration ==="
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
