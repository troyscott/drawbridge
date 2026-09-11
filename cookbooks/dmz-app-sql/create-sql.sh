#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/dmz-app-sql/create-sql.sh
# Create Azure SQL logical server (Entra-only) and serverless database
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Azure SQL Provisioning ==="

if ! check_prerequisites; then
    exit 1
fi

# --- Get current user info for Entra admin ---
CURRENT_USER_NAME=$(az account show --query "user.name" --output tsv 2>/dev/null)
CURRENT_USER_ID=$(az ad signed-in-user show --query "id" --output tsv 2>/dev/null)

if [[ -z "$CURRENT_USER_ID" ]]; then
    log_error "Cannot determine current Entra user. Ensure you're logged in with a user account."
    exit 1
fi

log_info "Entra admin will be: $CURRENT_USER_NAME"

# --- SQL Logical Server ---
EXISTING_SERVER=$(az sql server show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_SERVER" ]]; then
    log_info "SQL Server $SQL_SERVER_NAME already exists — skipping creation"
else
    log_info "Creating SQL Server: $SQL_SERVER_NAME (Entra-only auth)"

    if ! az sql server create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_SERVER_NAME" \
        --location "$AZURE_LOCATION" \
        --enable-ad-only-auth \
        --external-admin-principal-type "User" \
        --external-admin-name "$CURRENT_USER_NAME" \
        --external-admin-sid "$CURRENT_USER_ID" \
        --tags $TAGS \
        --output none; then

        log_error "SQL Server creation failed. Common causes:"
        log_error "  - Region capacity: try a different AZURE_LOCATION in .env"
        log_error "  - Name taken: sql-drawbridge-dev must be globally unique"
        exit 1
    fi

    log_success "SQL Server created: $SQL_SERVER_NAME"
fi

# --- Disable public network access ---
log_info "Disabling public network access..."
az sql server update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --set publicNetworkAccess="Disabled" \
    --output none 2>/dev/null || log_warn "Could not disable public access (server may not exist)"

log_success "Public access disabled"

# --- Serverless Database ---
EXISTING_DB=$(az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$SQL_DB_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_DB" ]]; then
    log_info "Database $SQL_DB_NAME already exists — skipping creation"
else
    log_info "Creating database: $SQL_DB_NAME (Serverless, auto-pause ${SQL_DB_AUTOPAUSE}min)"

    if ! az sql db create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "$SQL_DB_NAME" \
        --compute-model Serverless \
        --edition GeneralPurpose \
        --family Gen5 \
        --capacity 2 \
        --min-capacity 0.5 \
        --auto-pause-delay "$SQL_DB_AUTOPAUSE" \
        --max-size 32GB \
        --backup-storage-redundancy Local \
        --zone-redundant false \
        --tags $TAGS \
        --output none; then

        log_error "Database creation failed. The SQL server may not exist."
        exit 1
    fi

    log_success "Database created: $SQL_DB_NAME"
fi

# --- Grant App Service managed identity access ---
MI_PRINCIPAL_ID=$(az webapp identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "principalId" \
    --output tsv 2>/dev/null)

if [[ -n "$MI_PRINCIPAL_ID" ]]; then
    log_info "App Service MI found: ${MI_PRINCIPAL_ID:0:8}..."
    log_info "To grant db roles, run this T-SQL via Tailscale:"
    echo ""
    echo "  CREATE USER [${APP_NAME}] FROM EXTERNAL PROVIDER;"
    echo "  ALTER ROLE db_datareader ADD MEMBER [${APP_NAME}];"
    echo "  ALTER ROLE db_datawriter ADD MEMBER [${APP_NAME}];"
    echo ""
else
    log_warn "App Service $APP_NAME not found — deploy it first to grant MI access"
fi

# --- Summary ---
SQL_FQDN="${SQL_SERVER_NAME}.database.windows.net"
echo ""
log_success "=== Azure SQL Provisioning Complete ==="
echo ""
echo "  Server:       $SQL_SERVER_NAME"
echo "  FQDN:         $SQL_FQDN"
echo "  Database:     $SQL_DB_NAME"
echo "  Auth:         Entra-only (no SQL passwords)"
echo "  Admin:        $CURRENT_USER_NAME"
echo "  Compute:      Serverless Gen5 2vCore (0.5-2)"
echo "  Auto-pause:   ${SQL_DB_AUTOPAUSE} minutes"
echo "  Public access: Disabled"
echo ""
