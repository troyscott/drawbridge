#!/usr/bin/env bash
# =============================================================================
# drawbridge/cookbooks/simple-app-easyauth/create-appservice.sh
# Create the resource group, App Service Plan, Web App, and Entra ID auth.
# No VNet, no private backend. Idempotent — safe to re-run.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

log_info "=== App Service Provisioning ==="

if ! check_prerequisites; then
    exit 1
fi

# --- Resource Group ---
if resource_group_exists; then
    log_info "Resource group $RESOURCE_GROUP already exists — skipping"
else
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --tags $TAGS \
        --output none

    log_success "Resource group created: $RESOURCE_GROUP"
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

    if ! az appservice plan create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ASP_NAME" \
        --sku "$ASP_SKU" \
        --is-linux \
        --location "$AZURE_LOCATION" \
        --tags $TAGS \
        --output none; then

        log_error "App Service Plan creation failed. Common causes:"
        log_error "  - Quota limit: request a quota increase in Azure Portal"
        log_error "  - Region capacity: try a different AZURE_LOCATION in .env"
        exit 1
    fi

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

    if ! az webapp create \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$ASP_NAME" \
        --name "$APP_NAME" \
        --runtime "PYTHON:3.12" \
        --tags $TAGS \
        --output none; then

        log_error "Web App creation failed. The App Service Plan may not exist."
        exit 1
    fi

    log_success "Web App created: $APP_NAME"
fi

# --- System-assigned Managed Identity ---
log_info "Enabling system-assigned managed identity..."
MI_PRINCIPAL_ID=$(az webapp identity assign \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --query "principalId" \
    --output tsv 2>/dev/null)

if [[ -z "$MI_PRINCIPAL_ID" ]]; then
    log_error "Failed to enable managed identity on $APP_NAME"
    exit 1
fi

log_success "Managed Identity enabled (Principal ID: ${MI_PRINCIPAL_ID:0:8}...)"

# --- App settings ---
log_info "Configuring app settings..."
az webapp config appsettings set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --settings \
        SCM_DO_BUILD_DURING_DEPLOYMENT=true \
        WEBSITE_HTTPLOGGING_RETENTION_DAYS=3 \
        PYTHONDONTWRITEBYTECODE=1 \
    --output none || { log_error "Failed to set app settings"; exit 1; }

log_success "App settings configured"

# --- Always-on + HTTPS only ---
log_info "Enabling always-on and HTTPS-only..."
az webapp config set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --always-on true \
    --output none 2>/dev/null

az webapp update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --https-only true \
    --output none || log_warn "Could not enforce HTTPS-only"

# --- Entra ID authentication (Easy Auth v2) ---
log_info "Configuring Entra ID authentication..."

ENTRA_APP_NAME="app-${PROJECT}-${ENV}-auth"
EXISTING_ENTRA_APP=$(az ad app list \
    --display-name "$ENTRA_APP_NAME" \
    --query "[0].appId" \
    --output tsv 2>/dev/null)

if [[ -n "$EXISTING_ENTRA_APP" ]]; then
    ENTRA_CLIENT_ID="$EXISTING_ENTRA_APP"
    log_info "Entra app registration already exists: $ENTRA_CLIENT_ID"
else
    APP_URL="https://${APP_NAME}.azurewebsites.net"

    ENTRA_CLIENT_ID=$(az ad app create \
        --display-name "$ENTRA_APP_NAME" \
        --sign-in-audience "AzureADMyOrg" \
        --web-redirect-uris "${APP_URL}/.auth/login/aad/callback" \
        --enable-id-token-issuance true \
        --query "appId" \
        --output tsv 2>/dev/null)

    if [[ -z "$ENTRA_CLIENT_ID" ]]; then
        log_error "Failed to create Entra app registration"
        exit 1
    fi

    log_success "Entra app registration created: $ENTRA_CLIENT_ID"
    az ad sp create --id "$ENTRA_CLIENT_ID" --output none 2>/dev/null
    log_success "Service principal created"
fi

TENANT_ID=$(az account show --query "tenantId" --output tsv)
ISSUER_URL="https://login.microsoftonline.com/${TENANT_ID}/v2.0"

az webapp auth update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$APP_NAME" \
    --enabled true \
    --action LoginWithAzureActiveDirectory \
    --output none 2>/dev/null

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
echo "  Auth:          Entra ID (Easy Auth v2)"
echo "  Entra App:     $ENTRA_CLIENT_ID"
echo ""
log_info "Visit the URL above — you'll be redirected to sign in with Entra ID."
echo ""
