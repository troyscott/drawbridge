#!/usr/bin/env bash
# =============================================================================
# drawbridge/lib/common.sh
# Generic helpers shared by every cookbook. Sourced from each cookbook's
# config.sh — never sourced directly by a create-*.sh/delete-*.sh script.
# =============================================================================

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $*"
}

log_success() {
    echo -e "\033[0;32m[OK]\033[0m $*"
}

log_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

# Check that required CLI tools are available and Azure is logged in.
# Expects AZURE_SUBSCRIPTION_ID to already be set by the caller's config.sh.
check_prerequisites() {
    local missing=0
    for cmd in az jq; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done

    if [[ -z "$AZURE_SUBSCRIPTION_ID" ]]; then
        log_error "AZURE_SUBSCRIPTION_ID is not set. Add it to .env or export it."
        missing=1
    fi

    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Run: az login"
        missing=1
    fi

    if [[ $missing -eq 1 ]]; then
        return 1
    fi

    az account set --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null
    log_success "Using subscription: $(az account show --query name -o tsv)"
    return 0
}

# Check if a resource group exists. Expects RESOURCE_GROUP to be set.
resource_group_exists() {
    az group exists --name "$RESOURCE_GROUP" 2>/dev/null | grep -q "true"
}

# Run an az command and exit on failure.
run_az() {
    local description="$1"
    shift
    if "$@"; then
        return 0
    else
        log_error "Failed: $description"
        log_error "Command: $*"
        return 1
    fi
}
