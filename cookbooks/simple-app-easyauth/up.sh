#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/up.sh
# Orchestrator: bring up the App Service environment.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   🏰 simple-app-easyauth — Bring Up       ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

if ! check_prerequisites; then
    log_error "Prerequisites check failed. Run 'make validate COOKBOOK=simple-app-easyauth' for details."
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

if bash "$SCRIPT_DIR/create-appservice.sh"; then
    ELAPSED=$SECONDS
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║   🏰 simple-app-easyauth — Complete       ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""
    log_info "Time: $((ELAPSED / 60))m $((ELAPSED % 60))s"
    echo ""
    log_info "Next steps:"
    echo "  1. Visit: https://${APP_NAME}.azurewebsites.net"
    echo "  2. Deploy app code: make deploy COOKBOOK=simple-app-easyauth"
    echo "  3. Check status: make status COOKBOOK=simple-app-easyauth"
    echo ""
    exit 0
else
    log_error "Provisioning failed. Review the output above and re-run 'make up COOKBOOK=simple-app-easyauth' (idempotent)."
    exit 1
fi
