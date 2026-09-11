#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/down.sh
# Orchestrator: tear down the App Service environment.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   🏰 simple-app-easyauth — Tear Down      ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

if ! check_prerequisites; then
    log_error "Prerequisites check failed."
    exit 1
fi

print_config

if [[ "$1" != "--force" ]]; then
    echo ""
    log_warn "This will DELETE all resources in: $RESOURCE_GROUP"
    log_warn "This action cannot be undone."
    read -r -p "Type the environment name to confirm [$ENV]: " confirm
    if [[ "$confirm" != "$ENV" ]]; then
        log_info "Aborted. (Expected: $ENV)"
        exit 0
    fi
fi

SECONDS=0
bash "$SCRIPT_DIR/delete-appservice.sh"
ELAPSED=$SECONDS

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   🏰 simple-app-easyauth — Teardown Done  ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
log_info "Time: $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo ""
