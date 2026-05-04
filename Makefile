# =============================================================================
# Drawbridge Makefile
# Developer convenience targets for Azure infrastructure management
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

SCRIPTS_DIR := scripts
CONFIG := $(SCRIPTS_DIR)/config.sh

# --- Primary targets ---

.PHONY: up
up: validate ## Bring up the entire Azure environment
	@bash $(SCRIPTS_DIR)/up.sh

.PHONY: down
down: ## Tear down the entire Azure environment
	@bash $(SCRIPTS_DIR)/down.sh

.PHONY: status
status: ## Show status of all Azure resources
	@bash $(SCRIPTS_DIR)/status.sh

# --- Setup ---

.PHONY: init
init: ## Initial setup: copy .env.template → .env
	@if [ ! -f .env ]; then \
		cp .env.template .env; \
		echo "Created .env from template. Edit it with your values:"; \
		echo "  $${EDITOR:-vi} .env"; \
	else \
		echo ".env already exists. Edit it directly:"; \
		echo "  $${EDITOR:-vi} .env"; \
	fi

.PHONY: validate
validate: ## Validate prerequisites and configuration
	@bash -c 'source $(CONFIG) && check_prerequisites && print_config'

.PHONY: config
config: ## Print current configuration
	@bash -c 'source $(CONFIG) && print_config'

# --- Individual resource targets ---

.PHONY: up-network
up-network: ## Create resource group, VNet, and subnets
	@bash $(SCRIPTS_DIR)/create-network.sh

.PHONY: up-sql
up-sql: ## Create Azure SQL server and database
	@bash $(SCRIPTS_DIR)/create-sql.sh

.PHONY: up-storage
up-storage: ## Create Storage account and Key Vault
	@bash $(SCRIPTS_DIR)/create-storage.sh

.PHONY: up-endpoints
up-endpoints: ## Create private endpoints and DNS zones
	@bash $(SCRIPTS_DIR)/create-private-endpoints.sh

.PHONY: up-appservice
up-appservice: ## Create App Service Plan and Web App
	@bash $(SCRIPTS_DIR)/create-appservice.sh

.PHONY: up-monitoring
up-monitoring: ## Create Application Insights
	@bash $(SCRIPTS_DIR)/create-monitoring.sh

.PHONY: up-tailscale
up-tailscale: ## Create Tailscale subnet router VM
	@bash $(SCRIPTS_DIR)/create-tailscale.sh

# --- Utilities ---

.PHONY: deploy
deploy: ## Deploy application code to App Service
	@bash $(SCRIPTS_DIR)/deploy-app.sh

.PHONY: logs
logs: ## Stream App Service logs
	@bash -c 'source $(CONFIG) && az webapp log tail --name $$APP_NAME --resource-group $$RESOURCE_GROUP'

.PHONY: ssh
ssh: ## SSH into App Service container
	@bash -c 'source $(CONFIG) && az webapp ssh --name $$APP_NAME --resource-group $$RESOURCE_GROUP'

# --- Help ---

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "Drawbridge — Azure DevOps Toolkit"
	@echo "================================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  make init       # Create .env from template"
	@echo "  make validate   # Check prerequisites"
	@echo "  make up         # Bring up everything"
	@echo "  make status     # Check resource status"
	@echo "  make down       # Tear it all down"
	@echo ""
