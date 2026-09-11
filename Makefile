# =============================================================================
# Drawbridge Makefile
# Developer convenience targets for a cookbook-based Azure infrastructure
# toolkit. Every target except `help`, `init`, and `list-cookbooks` requires
# COOKBOOK=<name> — see `make list-cookbooks`.
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

COOKBOOKS_DIR := cookbooks
COOKBOOK ?=
COOKBOOK_DIR := $(COOKBOOKS_DIR)/$(COOKBOOK)
CONFIG := $(COOKBOOK_DIR)/config.sh

define require_cookbook
	@test -n "$(COOKBOOK)" || { echo "COOKBOOK is required. Usage: make $@ COOKBOOK=<name>"; echo ""; $(MAKE) --no-print-directory list-cookbooks; exit 1; }
endef

# --- Primary targets ---

.PHONY: up
up: validate ## Bring up a cookbook's environment. Usage: make up COOKBOOK=dmz-app-sql
	@bash $(COOKBOOK_DIR)/up.sh

.PHONY: down
down: ## Tear down a cookbook's environment. Usage: make down COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash $(COOKBOOK_DIR)/down.sh

.PHONY: status
status: ## Show a cookbook's resource status. Usage: make status COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash $(COOKBOOK_DIR)/status.sh

# --- Setup ---

.PHONY: init
init: ## Initial setup: copy .env.template → .env (shared across all cookbooks)
	@if [ ! -f .env ]; then \
		cp .env.template .env; \
		echo "Created .env from template. Edit it with your values:"; \
		echo "  $${EDITOR:-vi} .env"; \
	else \
		echo ".env already exists. Edit it directly:"; \
		echo "  $${EDITOR:-vi} .env"; \
	fi

.PHONY: list-cookbooks
list-cookbooks: ## List available cookbooks
	@echo "Available cookbooks:"
	@for d in $(COOKBOOKS_DIR)/*/; do echo "  - $$(basename $$d)"; done

.PHONY: validate
validate: ## Check prerequisites and print config. Usage: make validate COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash -c 'source $(CONFIG) && check_prerequisites && print_config'

.PHONY: config
config: ## Print a cookbook's resolved configuration. Usage: make config COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash -c 'source $(CONFIG) && print_config'

# --- Utilities ---

.PHONY: deploy
deploy: ## Deploy application code to a cookbook's App Service. Usage: make deploy COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash $(COOKBOOK_DIR)/deploy-app.sh

.PHONY: logs
logs: ## Stream a cookbook's App Service logs. Usage: make logs COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash -c 'source $(CONFIG) && az webapp log tail --name $$APP_NAME --resource-group $$RESOURCE_GROUP'

.PHONY: ssh
ssh: ## SSH into a cookbook's App Service container. Usage: make ssh COOKBOOK=dmz-app-sql
	$(call require_cookbook)
	@bash -c 'source $(CONFIG) && az webapp ssh --name $$APP_NAME --resource-group $$RESOURCE_GROUP'

# --- Help ---

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "Drawbridge — Azure POC Cookbook Toolkit"
	@echo "========================================"
	@echo ""
	@echo "Usage: make [target] COOKBOOK=<name>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  make init                            # Create .env from template"
	@echo "  make list-cookbooks                  # See available recipes"
	@echo "  make validate COOKBOOK=dmz-app-sql    # Check prerequisites"
	@echo "  make up COOKBOOK=dmz-app-sql          # Bring up that cookbook"
	@echo "  make status COOKBOOK=dmz-app-sql      # Check resource status"
	@echo "  make down COOKBOOK=dmz-app-sql        # Tear it down"
	@echo ""
