#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-tailscale.sh
# Deploy a lightweight Linux VM as a Tailscale subnet router
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== Tailscale Subnet Router Provisioning ==="

# --- Prerequisites ---
if ! check_prerequisites; then
    exit 1
fi

if [[ -z "$TS_AUTHKEY" ]]; then
    log_error "TS_AUTHKEY is not set."
    log_error "Generate one at: https://login.tailscale.com/admin/settings/keys"
    log_error "Then add it to your .env file."
    exit 1
fi

# --- Derived names ---
TS_NIC_NAME="nic-${TS_VM_NAME}"
TS_NSG_NAME="nsg-${TS_VM_NAME}"
TS_OS_DISK="osdisk-${TS_VM_NAME}"

# --- Check if VM already exists ---
EXISTING_VM=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_VM_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_VM" ]]; then
    log_info "VM $TS_VM_NAME already exists — skipping creation"
    VM_STATE=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_VM_NAME" \
        --show-details \
        --query "powerState" \
        --output tsv 2>/dev/null)
    log_info "Current state: $VM_STATE"

    if [[ "$VM_STATE" == "VM deallocated" ]]; then
        log_info "Starting deallocated VM..."
        az vm start \
            --resource-group "$RESOURCE_GROUP" \
            --name "$TS_VM_NAME" \
            --output none
        log_success "VM started"
    fi
    exit 0
fi

# --- NSG: allow outbound only (Tailscale needs outbound UDP/443) ---
log_info "Creating NSG: $TS_NSG_NAME"
az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_NSG_NAME" \
    --location "$AZURE_LOCATION" \
    --tags $TAGS \
    --output none 2>/dev/null

# --- NIC: in snet-ts, no public IP ---
log_info "Creating NIC: $TS_NIC_NAME (no public IP)"

EXISTING_NIC=$(az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_NIC_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -z "$EXISTING_NIC" ]]; then
    az network nic create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$TS_NIC_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SNET_TS_NAME" \
        --network-security-group "$TS_NSG_NAME" \
        --location "$AZURE_LOCATION" \
        --ip-forwarding true \
        --tags $TAGS \
        --output none

    log_success "NIC created with IP forwarding enabled"
else
    log_info "NIC $TS_NIC_NAME already exists — skipping"
fi

# --- Cloud-init script ---
# The auth key is injected via custom-data; it is NOT stored in the script file.
CLOUD_INIT_FILE=$(mktemp /tmp/drawbridge-cloud-init-XXXXXX.yaml)

cat > "$CLOUD_INIT_FILE" << CLOUDINIT
#cloud-config
package_update: true
package_upgrade: true

write_files:
  - path: /etc/sysctl.d/99-tailscale.conf
    content: |
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1

runcmd:
  # Enable IP forwarding immediately
  - sysctl -p /etc/sysctl.d/99-tailscale.conf

  # Install Tailscale
  - curl -fsSL https://tailscale.com/install.sh | sh

  # Bring up Tailscale as a subnet router
  - tailscale up --authkey=${TS_AUTHKEY} --advertise-routes=${VNET_CIDR} --accept-dns=false --hostname=${TS_VM_NAME}

  # Log success
  - echo "Tailscale subnet router configured: advertising ${VNET_CIDR}" | tee /var/log/drawbridge-setup.log
CLOUDINIT

log_info "Cloud-init prepared (auth key injected at runtime, not stored in repo)"

# --- Create VM ---
log_info "Creating VM: $TS_VM_NAME ($TS_VM_SIZE)"
log_info "Image: $TS_VM_IMAGE"
log_info "This may take 2-3 minutes..."

az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_VM_NAME" \
    --nics "$TS_NIC_NAME" \
    --image "$TS_VM_IMAGE" \
    --size "$TS_VM_SIZE" \
    --os-disk-name "$TS_OS_DISK" \
    --os-disk-size-gb 30 \
    --storage-sku StandardSSD_LRS \
    --admin-username drawbridge \
    --generate-ssh-keys \
    --custom-data "$CLOUD_INIT_FILE" \
    --tags $TAGS \
    --output none

# Clean up temp file
rm -f "$CLOUD_INIT_FILE"

log_success "VM created: $TS_VM_NAME"

# --- Enable auto-shutdown to save costs (11 PM local, no notification) ---
log_info "Configuring auto-shutdown at 23:00 UTC..."
az vm auto-shutdown \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_VM_NAME" \
    --time "2300" \
    --output none 2>/dev/null

log_success "Auto-shutdown configured"

# --- Get private IP ---
PRIVATE_IP=$(az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$TS_NIC_NAME" \
    --query "ipConfigurations[0].privateIPAddress" \
    --output tsv 2>/dev/null)

# --- Summary ---
echo ""
log_success "=== Tailscale Subnet Router Ready ==="
echo ""
echo "  VM:            $TS_VM_NAME"
echo "  Size:          $TS_VM_SIZE"
echo "  Private IP:    $PRIVATE_IP"
echo "  Subnet:        $SNET_TS_NAME ($SNET_TS_CIDR)"
echo "  Advertised:    $VNET_CIDR"
echo "  Auto-shutdown: 23:00 UTC"
echo ""
log_info "Next steps:"
echo "  1. Go to https://login.tailscale.com/admin/machines"
echo "  2. Find '$TS_VM_NAME' and approve the advertised subnet routes"
echo "  3. On your Mac, enable 'Accept routes' in Tailscale preferences"
echo "  4. Verify: ping $PRIVATE_IP (from your Tailscale-connected Mac)"
echo ""
