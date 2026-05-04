#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/up.sh
# Orchestrator: bring up the entire Azure environment
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

# --- Step 1: Network ---
log_info "Step 1/7: Creating resource group, VNet, and subnets..."
if [[ -f "$SCRIPT_DIR/create-network.sh" ]]; then
    bash "$SCRIPT_DIR/create-network.sh"
else
    log_warn "create-network.sh not found — skipping (implement in issue #2)"
fi

# --- Step 2: SQL ---
log_info "Step 2/7: Creating Azure SQL server and database..."
if [[ -f "$SCRIPT_DIR/create-sql.sh" ]]; then
    bash "$SCRIPT_DIR/create-sql.sh"
else
    log_warn "create-sql.sh not found — skipping (implement in issue #5)"
fi

# --- Step 3: Storage + Key Vault ---
log_info "Step 3/7: Creating Storage account and Key Vault..."
if [[ -f "$SCRIPT_DIR/create-storage.sh" ]]; then
    bash "$SCRIPT_DIR/create-storage.sh"
else
    log_warn "create-storage.sh not found — skipping (implement in issue #6)"
fi

# --- Step 4: Private Endpoints ---
log_info "Step 4/7: Creating private endpoints and DNS zones..."
if [[ -f "$SCRIPT_DIR/create-private-endpoints.sh" ]]; then
    bash "$SCRIPT_DIR/create-private-endpoints.sh"
else
    log_warn "create-private-endpoints.sh not found — skipping (implement in issue #7)"
fi

# --- Step 5: App Service ---
log_info "Step 5/7: Creating App Service..."
if [[ -f "$SCRIPT_DIR/create-appservice.sh" ]]; then
    bash "$SCRIPT_DIR/create-appservice.sh"
else
    log_warn "create-appservice.sh not found — skipping (implement in issue #4)"
fi

# --- Step 6: Monitoring ---
log_info "Step 6/7: Creating Application Insights..."
if [[ -f "$SCRIPT_DIR/create-monitoring.sh" ]]; then
    bash "$SCRIPT_DIR/create-monitoring.sh"
else
    log_warn "create-monitoring.sh not found — skipping (implement in issue #8)"
fi

# --- Step 7: Tailscale ---
log_info "Step 7/7: Creating Tailscale subnet router..."
if [[ -f "$SCRIPT_DIR/create-tailscale.sh" ]]; then
    bash "$SCRIPT_DIR/create-tailscale.sh"
else
    log_warn "create-tailscale.sh not found — skipping (implement in issue #3)"
fi

# --- Summary ---
ELAPSED=$SECONDS
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🏰 Drawbridge — Complete             ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
log_success "Environment created in $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo ""
log_info "Next steps:"
echo "  1. Install Tailscale on your Mac: https://tailscale.com/download"
echo "  2. Approve the subnet router in Tailscale admin console"
echo "  3. Visit your app: https://${APP_NAME}.azurewebsites.net"
echo "  4. Deploy code: make deploy"
echo ""
