#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/delete-tailscale.sh
# Remove Tailscale subnet router VM and associated resources
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Tailscale Subnet Router Teardown ==="

if ! check_prerequisites; then
    exit 1
fi

if ! resource_group_exists; then
    log_warn "Resource group $RESOURCE_GROUP does not exist. Nothing to delete."
    exit 0
fi

# --- Derived names ---
TS_NIC_NAME="nic-${TS_VM_NAME}"
TS_NSG_NAME="nsg-${TS_VM_NAME}"
TS_OS_DISK="osdisk-${TS_VM_NAME}"

# --- Delete VM (also deletes OS disk when using --force-deletion) ---
if az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_VM_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting VM: $TS_VM_NAME (and OS disk)"
    az vm delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_VM_NAME" \
        --force-deletion yes \
        --yes \
        --output none
    log_success "Deleted VM: $TS_VM_NAME"
else
    log_info "VM $TS_VM_NAME not found — skipping"
fi

# --- Delete NIC ---
if az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_NIC_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting NIC: $TS_NIC_NAME"
    az network nic delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_NIC_NAME" \
        --output none
    log_success "Deleted NIC: $TS_NIC_NAME"
else
    log_info "NIC $TS_NIC_NAME not found — skipping"
fi

# --- Delete NSG ---
if az network nsg show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_NSG_NAME" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting NSG: $TS_NSG_NAME"
    az network nsg delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_NSG_NAME" \
        --output none
    log_success "Deleted NSG: $TS_NSG_NAME"
else
    log_info "NSG $TS_NSG_NAME not found — skipping"
fi

# --- Clean up orphaned OS disk (if VM delete didn't remove it) ---
if az disk show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_OS_DISK" \
    --query "name" \
    --output tsv &>/dev/null; then

    log_info "Deleting orphaned OS disk: $TS_OS_DISK"
    az disk delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_OS_DISK" \
        --yes \
        --output none
    log_success "Deleted disk: $TS_OS_DISK"
fi

echo ""
log_success "=== Tailscale Subnet Router Teardown Complete ==="
echo ""
log_info "Remember to remove the device from your Tailscale admin console:"
echo "  https://login.tailscale.com/admin/machines"
echo ""
