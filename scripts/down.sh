#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/down.sh
# Orchestrator: tear down the entire Azure environment
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🏰 Drawbridge — Tear Down            ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

if ! check_prerequisites; then
    log_error "Prerequisites check failed."
    exit 1
fi

print_config

# --- Confirm unless --force ---
if [[ "$1" != "--force" ]]; then
    echo ""
    log_warn "This will DELETE all resources in: $RESOURCE_GROUP"
    read -r -p "Are you sure? Type the environment name to confirm [$ENV]: " confirm
    if [[ "$confirm" != "$ENV" ]]; then
        log_info "Aborted. (Expected: $ENV)"
        exit 0
    fi
fi

SECONDS=0

# --- Delete resource group (removes everything inside) ---
log_info "Deleting resource group: $RESOURCE_GROUP"
log_info "This may take several minutes..."

if az group exists --name "$RESOURCE_GROUP" 2>/dev/null | grep -q "true"; then
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait

    log_success "Resource group deletion initiated (running in background)."
    log_info "Monitor progress: az group show -n $RESOURCE_GROUP --query properties.provisioningState"
else
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
fi

# --- Purge Key Vault (soft-deleted vaults block re-creation) ---
log_info "Checking for soft-deleted Key Vault..."
if az keyvault list-deleted --query "[?name=='$KEYVAULT_NAME']" -o tsv 2>/dev/null | grep -q "$KEYVAULT_NAME"; then
    log_info "Purging soft-deleted Key Vault: $KEYVAULT_NAME"
    az keyvault purge --name "$KEYVAULT_NAME" --no-wait 2>/dev/null
    log_success "Key Vault purge initiated."
else
    log_info "No soft-deleted Key Vault found."
fi

ELAPSED=$SECONDS
echo ""
log_success "Teardown initiated in $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo ""
log_info "Note: Resource group deletion runs asynchronously."
log_info "Full cleanup may take 5-10 minutes."
echo ""
