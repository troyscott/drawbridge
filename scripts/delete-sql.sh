#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-sql.sh
# Remove Azure SQL database and logical server
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Azure SQL Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Delete database first ---
if az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$SQL_DB_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting database: $SQL_DB_NAME"
    az sql db delete \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "$SQL_DB_NAME" \
        --yes \
        --output none
    log_success "Deleted database: $SQL_DB_NAME"
else
    log_info "Database $SQL_DB_NAME not found — skipping"
fi

# --- Delete SQL server ---
if az sql server show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SQL_SERVER_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting SQL Server: $SQL_SERVER_NAME"
    az sql server delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_SERVER_NAME" \
        --yes \
        --output none
    log_success "Deleted SQL Server: $SQL_SERVER_NAME"
else
    log_info "SQL Server $SQL_SERVER_NAME not found — skipping"
fi

echo ""
log_success "=== Azure SQL Teardown Complete ==="
echo ""
