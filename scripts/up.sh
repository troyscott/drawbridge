#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/up.sh
# Orchestrator: bring up the entire Azure environment
# Calls each create script in dependency order with error handling
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🏰 Drawbridge — Bring Up            ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# --- Validate prerequisites ---
if ! check_prerequisites; then
    log_error "Prerequisites check failed. Run 'make validate' for details."
    exit 1
fi

print_config

echo ""
read -r -p "Proceed with environment creation? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Aborted."
    exit 0
fi

SECONDS=0
FAILED=0

# --- Helper: run a step, track failures ---
run_step() {
    local step_num="$1"
    local total="$2"
    local description="$3"
    local script="$4"

    echo ""
    log_info "Step ${step_num}/${total}: ${description}"

    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        log_error "$script not found"
        FAILED=$((FAILED + 1))
        return 1
    fi

    if bash "$SCRIPT_DIR/$script"; then
        log_success "Step ${step_num} complete"
    else
        log_error "Step ${step_num} failed: $script"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# --- Execute in dependency order ---
TOTAL=7

run_step 1 $TOTAL "Resource group, VNet, and subnets"   "create-network.sh"
run_step 2 $TOTAL "Azure SQL server and database"        "create-sql.sh"
run_step 3 $TOTAL "Storage account and Key Vault"        "create-storage.sh"
run_step 4 $TOTAL "Private endpoints and DNS zones"      "create-private-endpoints.sh"
run_step 5 $TOTAL "App Service with Entra ID auth"       "create-appservice.sh"
run_step 6 $TOTAL "Application Insights"                 "create-monitoring.sh"
run_step 7 $TOTAL "Tailscale subnet router"              "create-tailscale.sh"

# --- Summary ---
ELAPSED=$SECONDS
echo ""
echo "╔═══════════════════════════════════════════╗"
if [[ $FAILED -eq 0 ]]; then
    echo "║       🏰 Drawbridge — Complete             ║"
else
    echo "║       🏰 Drawbridge — Partial ($FAILED failed)   ║"
fi
echo "╚═══════════════════════════════════════════╝"
echo ""

log_info "Time: $((ELAPSED / 60))m $((ELAPSED % 60))s"

if [[ $FAILED -gt 0 ]]; then
    log_warn "$FAILED step(s) failed. Review the output above and re-run 'make up' (idempotent)."
fi

echo ""
log_info "Environment summary:"
echo "  App URL:   https://${APP_NAME}.azurewebsites.net"
echo "  SQL FQDN:  ${SQL_SERVER_NAME}.database.windows.net"
echo "  Storage:   ${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
echo "  Key Vault: ${KEYVAULT_NAME}.vault.azure.net"
echo ""
log_info "Next steps:"
echo "  1. Install Tailscale: https://tailscale.com/download"
echo "  2. Approve subnet routes: https://login.tailscale.com/admin/machines"
echo "  3. Test DNS: nslookup ${SQL_SERVER_NAME}.database.windows.net"
echo "  4. Deploy app code: make deploy"
echo "  5. Check status: make status"
echo ""

exit $FAILED
