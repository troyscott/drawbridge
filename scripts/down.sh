#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/down.sh
# Orchestrator: tear down the entire Azure environment
# Deletes the resource group (removes all resources) + Entra app + KV purge
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
    log_warn "This action cannot be undone."
    read -r -p "Type the environment name to confirm [$ENV]: " confirm
    if [[ "$confirm" != "$ENV" ]]; then
        log_info "Aborted. (Expected: $ENV)"
        exit 0
    fi
fi

SECONDS=0

# --- Delete Entra app registration (lives outside RG) ---
ENTRA_APP_NAME="app-${PROJECT}-${ENV}-auth"
ENTRA_APP_ID=$(az ad app list \
    --display-name "$ENTRA_APP_NAME" \
    --query "[0].id" \
    --output tsv 2>/dev/null)

if [[ -n "$ENTRA_APP_ID" ]]; then
    log_info "Deleting Entra app registration: $ENTRA_APP_NAME"
    az ad app delete --id "$ENTRA_APP_ID" --output none 2>/dev/null
    log_success "Deleted Entra app registration"
else
    log_info "No Entra app registration found — skipping"
fi

# --- Delete resource group (removes everything inside) ---
if az group exists --name "$RESOURCE_GROUP" 2>/dev/null | grep -q "true"; then
    log_info "Deleting resource group: $RESOURCE_GROUP"
    log_info "This may take 5-10 minutes..."

    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none

    log_success "Resource group deletion initiated (running in background)"
else
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
fi

# --- Purge Key Vault (soft-deleted vaults block re-creation) ---
log_info "Checking for soft-deleted Key Vault..."
if az keyvault list-deleted \
    --query "[?name=='$KEYVAULT_NAME']" \
    --output tsv 2>/dev/null | grep -q "$KEYVAULT_NAME"; then

    log_info "Purging soft-deleted Key Vault: $KEYVAULT_NAME"
    az keyvault purge --name "$KEYVAULT_NAME" --no-wait --output none 2>/dev/null
    log_success "Key Vault purge initiated"
else
    log_info "No soft-deleted Key Vault found"
fi

ELAPSED=$SECONDS
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🏰 Drawbridge — Teardown Initiated   ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
log_info "Time: $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo ""
log_info "Resource group deletion runs asynchronously."
log_info "Monitor: az group show -n $RESOURCE_GROUP --query properties.provisioningState"
echo ""
log_info "Remember to remove the Tailscale device:"
echo "  https://login.tailscale.com/admin/machines"
echo ""
