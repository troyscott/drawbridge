#!/usr/bin/env bash
# =============================================================================
# drawbridge/scripts/create-appservice.sh
# Create App Service Plan, Web App, VNet integration, and Entra ID auth
# Idempotent — safe to re-run
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== App Service Provisioning ==="

# --- Prerequisites ---
if ! check_prerequisites; then
    exit 1
fi

# --- App Service Plan ---
EXISTING_ASP=$(az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ASP_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_ASP" ]]; then
    log_info "App Service Plan $ASP_NAME already exists — skipping"
else
    log_info "Creating App Service Plan: $ASP_NAME (SKU: $ASP_SKU, Linux)"
    az appservice plan create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ASP_NAME" \
        --sku "$ASP_SKU" \
        --is-linux \
        --location "$AZURE_LOCATION" \
        --tags $TAGS \
        --output none

    log_success "App Service Plan created: $ASP_NAME"
fi

# --- Web App ---
EXISTING_APP=$(az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_APP" ]]; then
    log_info "Web App $APP_NAME already exists — skipping creation"
else
    log_info "Creating Web App: $APP_NAME (Python 3.12)"
    az webapp create \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$ASP_NAME" \
        --name "$APP_NAME" \
        --runtime "PYTHON:3.12" \
        --tags $TAGS \
        --output none

    log_success "Web App created: $APP_NAME"
fi

# --- System-assigned Managed Identity ---
log_info "Enabling system-assigned managed identity..."
MI_PRINCIPAL_ID=$(az webapp identity assign \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "principalId" \
    --output tsv 2>/dev/null)

log_success "Managed Identity enabled (Principal ID: ${MI_PRINCIPAL_ID:0:8}...)"

# --- Startup command for FastAPI ---
log_info "Configuring startup command for FastAPI (gunicorn + uvicorn worker)..."
az webapp config set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --startup-file "gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 -w 2 --timeout 120 --access-logfile '-' --error-logfile '-' app.main:app" \
    --output none

log_success "Startup command configured"

# --- App settings ---
log_info "Configuring app settings..."
az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --settings \
        SCM_DO_BUILD_DURING_DEPLOYMENT=true \
        WEBSITE_HTTPLOGGING_RETENTION_DAYS=3 \
        PYTHONDONTWRITEBYTECODE=1 \
    --output none

log_success "App settings configured"

# --- Always-on (available on B1+) ---
log_info "Enabling always-on..."
az webapp config set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --always-on true \
    --output none 2>/dev/null

# --- HTTPS only ---
log_info "Enforcing HTTPS only..."
az webapp update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --https-only true \
    --output none

# --- VNet integration (outbound to private backend) ---
log_info "Configuring VNet integration with $SNET_APP_NAME..."

EXISTING_VNET_INT=$(az webapp vnet-integration list \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "[0].name" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_VNET_INT" ]]; then
    log_info "VNet integration already configured — skipping"
else
    az webapp vnet-integration add \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --vnet "$VNET_NAME" \
        --subnet "$SNET_APP_NAME" \
        --output none

    log_success "VNet integration configured: $VNET_NAME/$SNET_APP_NAME"
fi

# Route all outbound traffic through VNet (required for private endpoint resolution)
log_info "Enabling route-all for VNet integration..."
az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --settings WEBSITE_VNET_ROUTE_ALL=1 \
    --output none

# --- Entra ID authentication (Easy Auth v2) ---
log_info "Configuring Entra ID authentication (Easy Auth)..."

# Check if an Entra app registration already exists for this web app
ENTRA_APP_NAME="app-${PROJECT}-${ENV}-auth"
EXISTING_ENTRA_APP=$(az ad app list \
    --display-name "$ENTRA_APP_NAME" \
    --query "[0].appId" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_ENTRA_APP" ]]; then
    ENTRA_CLIENT_ID="$EXISTING_ENTRA_APP"
    log_info "Entra app registration already exists: $ENTRA_CLIENT_ID"
else
    # Create Entra app registration
    APP_URL="https://${APP_NAME}.azurewebsites.net"

    ENTRA_CLIENT_ID=$(az ad app create \
        --display-name "$ENTRA_APP_NAME" \
        --sign-in-audience "AzureADMyOrg" \
        --web-redirect-uris "${APP_URL}/.auth/login/aad/callback" \
        --enable-id-token-issuance true \
        --query "appId" \
        --output tsv 2>/dev/null)

    log_success "Entra app registration created: $ENTRA_CLIENT_ID"

    # Create a service principal for the app registration
    az ad sp create --id "$ENTRA_CLIENT_ID" --output none 2>/dev/null
    log_success "Service principal created"
fi

# Get tenant ID
TENANT_ID=$(az account show --query "tenantId" --output tsv)

# Configure Easy Auth v2 on the web app
ISSUER_URL="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

az webapp auth update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --enabled true \
    --action LoginWithAzureActiveDirectory \
    --output none 2>/dev/null

# Configure the Microsoft identity provider
az webapp auth microsoft update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --client-id "$ENTRA_CLIENT_ID" \
    --issuer "$ISSUER_URL" \
    --yes \
    --output none 2>/dev/null

log_success "Easy Auth configured with Entra ID"

# --- Logging ---
log_info "Enabling application logging..."
az webapp log config \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --web-server-logging filesystem \
    --docker-container-logging filesystem \
    --level information \
    --output none 2>/dev/null

# --- Summary ---
APP_URL="https://${APP_NAME}.azurewebsites.net"
echo ""
log_success "=== App Service Provisioning Complete ==="
echo ""
echo "  Plan:          $ASP_NAME (SKU: $ASP_SKU)"
echo "  Web App:       $APP_NAME"
echo "  URL:           $APP_URL"
echo "  Runtime:       Python 3.12"
echo "  Managed ID:    ${MI_PRINCIPAL_ID:0:8}..."
echo "  VNet:          $VNET_NAME/$SNET_APP_NAME"
echo "  Auth:          Entra ID (Easy Auth v2)"
echo "  Entra App:     $ENTRA_CLIENT_ID"
echo ""
log_info "Next steps:"
echo "  1. Deploy app code:  make deploy"
echo "  2. Stream logs:      make logs"
echo "  3. Visit:            $APP_URL"
echo ""
