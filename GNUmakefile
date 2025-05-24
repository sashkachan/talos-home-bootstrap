# Homelab Terraform Makefile

# Variables
SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
# Set tofu command
TOFU := tofu
KUBECTL := kubectl
VAULT := vault
TF_PROJECT_ROOT := $(shell pwd)/terraform

# Extract Cloudflare credentials
API_TOKEN := $(shell grep cloudflare_api_token "$(TF_PROJECT_ROOT)/terraform.tfvars" | cut -d '=' -f2 | tr -d '" ')
ACCOUNT_ID := $(shell grep cloudflare_account_id "$(TF_PROJECT_ROOT)/terraform.tfvars" | cut -d '=' -f2 | tr -d '" ')
EMAIL := $(shell grep cloudflare_account_email "$(TF_PROJECT_ROOT)/terraform.tfvars" | cut -d '=' -f2 | tr -d '" ')
ZONE_ID := $(shell grep cloudflare_zone_id "$(TF_PROJECT_ROOT)/terraform.tfvars" | cut -d '=' -f2 | tr -d '" ')

# Extract Hetzner Cloud credentials
HCLOUD_TOKEN := $(shell grep hcloud_token "$(TF_PROJECT_ROOT)/terraform.tfvars" | cut -d '=' -f2 | tr -d '" ')

# Standard Tofu commands
# Allow targeting specific modules with MODULE=module_name
.PHONY: tf-init
tf-init: ## Initialize Terraform/OpenTofu configuration
	$(TOFU) -chdir=$(TF_PROJECT_ROOT) init $(if $(MODULE),-target=module.$(MODULE),)

.PHONY: tf-plan
tf-plan: ## Show planned changes to infrastructure
	$(TOFU) -chdir=$(TF_PROJECT_ROOT) plan $(if $(MODULE),-target=module.$(MODULE),)

.PHONY: tf-apply
tf-apply: ## Apply changes to infrastructure
	TF_CLI_ARGS_apply="-parallelism=5" $(TOFU) -chdir=$(TF_PROJECT_ROOT) apply $(if $(AUTO_APPROVE),-auto-approve,) $(if $(MODULE),-target=module.$(MODULE),)

.PHONY: tf-destroy
tf-destroy: ## Destroy infrastructure
	TF_CLI_ARGS_destroy="-parallelism=5" $(TOFU) -chdir=$(TF_PROJECT_ROOT) destroy $(if $(MODULE),-target=module.$(MODULE),)

.PHONY: tf-output
tf-output: ## Show Terraform outputs
	$(TOFU) -chdir=$(TF_PROJECT_ROOT) output $(if $(MODULE),module.$(MODULE),)

.PHONY: tf-validate
tf-validate: ## Validate Terraform syntax
	$(TOFU) -chdir=$(TF_PROJECT_ROOT) validate

# Extended Terraform/OpenTofu validation commands
.PHONY: tf-validate-full tf-validate-lint tf-validate-fmt tf-validate-docs tf-fmt
tf-validate-full: tf-validate tf-validate-lint tf-validate-fmt tf-validate-docs ## Run all validations (syntax, lint, format, docs)
	@echo "Full validation completed"

tf-fmt: ## Auto-format all Terraform files
	@echo "Auto-formatting Terraform files..."
	@$(TOFU) -chdir=$(TF_PROJECT_ROOT) fmt -recursive

tf-validate-lint: ## Run TFLint to check for issues
	@echo "Running TFLint..."
	@if command -v tflint >/dev/null 2>&1; then \
		tflint --recursive $(TF_PROJECT_ROOT) || echo "TFLint found issues"; \
	else \
		echo "TFLint not installed. Install with: brew install tflint"; \
		exit 1; \
	fi

tf-validate-fmt: ## Check Terraform files formatting
	@echo "Running OpenTofu fmt check..."
	@$(TOFU) -chdir=$(TF_PROJECT_ROOT) fmt -check -recursive

tf-validate-docs: ## Verify module documentation is up-to-date
	@echo "Checking modules documentation with terraform-docs..."
	@if command -v terraform-docs >/dev/null 2>&1; then \
		cd $(TF_PROJECT_ROOT) && find . -type d -name "*.terraform" -prune -o -type f -name "*.tf" -print | xargs dirname | sort -u | xargs -I{} terraform-docs md {} --output-check || echo "Some modules have outdated documentation"; \
	else \
		echo "terraform-docs not installed. Install with: brew install terraform-docs"; \
		exit 1; \
	fi

# Port-forwarding commands
.PHONY: vault-port-forward
vault-port-forward: ## Forward local port 8200 to Vault service
	@$(KUBECTL) --context=default port-forward -n vault svc/vault 8200:8200 > /dev/null 2>&1 & \
	PID=$$!; \
	echo $$PID > .vault-port-forward.pid; \
	echo "Started Vault port forwarding (PID: $$PID)"

.PHONY: psql-port-forward
psql-port-forward: ## Forward local port 5432 to PostgreSQL service
	@$(KUBECTL) port-forward -n database svc/postgresql 5432:5432 > /dev/null 2>&1 & \
	PID=$$!; \
	echo $$PID > .psql-port-forward.pid; \
	echo "Started PostgreSQL port forwarding (PID: $$PID)"

.PHONY: argocd-port-forward
argocd-port-forward: ## Forward local port 8080 to ArgoCD service
	@$(KUBECTL) port-forward -n argocd svc/argocd-server 8080:80 > /dev/null 2>&1 & \
	PID=$$!; \
	echo $$PID > .argocd-port-forward.pid; \
	echo "Started ArgoCD port forwarding (PID: $$PID)"

.PHONY: clean
clean: ## Stop all port forwarding and clean up
	@if [ -f .vault-port-forward.pid ]; then \
		echo "Stopping Vault port forwarding (PID: $$(cat .vault-port-forward.pid))"; \
		kill $$(cat .vault-port-forward.pid) 2>/dev/null || true; \
		rm .vault-port-forward.pid; \
	else \
		echo "No active Vault port forwarding found"; \
	fi
	@if [ -f .psql-port-forward.pid ]; then \
		echo "Stopping PostgreSQL port forwarding (PID: $$(cat .psql-port-forward.pid))"; \
		kill $$(cat .psql-port-forward.pid) 2>/dev/null || true; \
		rm .psql-port-forward.pid; \
	else \
		echo "No active PostgreSQL port forwarding found"; \
	fi
	@if [ -f .argocd-port-forward.pid ]; then \
		echo "Stopping ArgoCD port forwarding (PID: $$(cat .argocd-port-forward.pid))"; \
		kill $$(cat .argocd-port-forward.pid) 2>/dev/null || true; \
		rm .argocd-port-forward.pid; \
	else \
		echo "No active ArgoCD port forwarding found"; \
	fi

# Talos cluster configuration
# --------------------------
# Define talosctl command and config paths
TALOSCTL := talosctl
SCRIPTS_PATH := $(shell pwd)
TALOS_CONFIG_PATH := $(SCRIPTS_PATH)/generated/talosconfig
KUBE_CONFIG_PATH := $(SCRIPTS_PATH)/generated/kubeconfig

.PHONY: talos-bootstrap talos-prepare talos-install talos-generate-configs talos-apply-configs talos-bootstrap-cluster talos-get-kubeconfig talos-install-crds talos-reset-cluster talos-upgrade

talos-bootstrap: ## Bootstrap Talos cluster (TALOS_VERSION required)
	@if [ -z "$(TALOS_VERSION)" ]; then \
		echo "Usage: make talos-bootstrap TALOS_VERSION=<version>"; \
		echo "Example: make talos-bootstrap TALOS_VERSION=v1.7.1"; \
		exit 1; \
	fi
	@mkdir -p $(SCRIPTS_PATH)/generated
	@echo "Bootstrapping Talos cluster with version $(TALOS_VERSION)..."
	@# Use set +e to prevent make from exiting when the SSH connection is closed during reboots
	@set +e; \
	HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/bootstrap_cluster.sh $(TALOS_VERSION); \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -ne 0 ]; then \
		echo "Bootstrap script exited with code $$EXIT_CODE"; \
		echo "This might be normal if SSH connections were closed during reboots."; \
		echo "Check the installed cluster with: make talos-health"; \
		echo "Or check individual nodes with: make talos CMD='version'"; \
	fi

# Stepped Talos bootstrap process (allows for step-by-step execution)
talos-prepare: ## Step 1: Prepare Talos environment (TALOS_VERSION required)
	@if [ -z "$(TALOS_VERSION)" ]; then \
		echo "Usage: make talos-prepare TALOS_VERSION=<version>"; \
		echo "Example: make talos-prepare TALOS_VERSION=v1.7.1"; \
		exit 1; \
	fi
	@mkdir -p $(SCRIPTS_PATH)/generated
	@echo "Step 1: Preparing environment for Talos installation with version $(TALOS_VERSION)..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/1_prepare_environment.sh $(TALOS_VERSION)
	@echo "Environment preparation complete. You can now run 'make talos-install'."

talos-install:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run 'make talos-prepare TALOS_VERSION=<version>' first."; \
		exit 1; \
	fi
	@echo "Step 2: Installing Talos on all nodes..."
	@# Use set +e to prevent make from exiting when the SSH connection is closed during reboots
	@set +e; \
	HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/2_install_talos.sh; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -ne 0 ]; then \
		echo "Installation script exited with code $$EXIT_CODE"; \
		echo "This might be normal if SSH connections were closed during reboots."; \
	fi
	@echo "Talos installation complete. You can now run 'make talos-generate-configs'."

talos-generate-configs:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run 'make talos-prepare TALOS_VERSION=<version>' first."; \
		exit 1; \
	fi
	@echo "Step 3: Generating Talos configurations..."
	@REGENERATE_SECRETS=$(REGENERATE_SECRETS) $(SCRIPTS_PATH)/3_generate_configs.sh
	@echo "Configuration generation complete. You can now run 'make talos-apply-configs'."

talos-apply-configs:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run previous steps first."; \
		exit 1; \
	fi
	@if [ ! -f "$(SCRIPTS_PATH)/generated/controlplane.yaml" ]; then \
		echo "Error: controlplane.yaml not found. Run 'make talos-generate-configs' first."; \
		exit 1; \
	fi
	@echo "Step 4: Applying Talos configurations to all nodes..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) INSECURE=$(INSECURE) $(SCRIPTS_PATH)/4_apply_configs.sh
	@echo "Configuration application complete. You can now run 'make talos-bootstrap-cluster'."

talos-bootstrap-cluster:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run previous steps first."; \
		exit 1; \
	fi
	@echo "Step 5: Bootstrapping Talos cluster..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/5_bootstrap_cluster.sh
	@echo "Cluster bootstrap complete. You can now run 'make talos-get-kubeconfig'."

talos-get-kubeconfig:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run previous steps first."; \
		exit 1; \
	fi
	@echo "Step 6: Retrieving kubeconfig and finalizing setup..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/6_get_kubeconfig.sh
	@echo "Kubeconfig retrieved. You can now run 'make talos-install-crds'."

talos-reset-cluster:
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Run 'make talos-prepare TALOS_VERSION=<version>' first."; \
		exit 1; \
	fi
	@echo "WARNING: This will reset ALL nodes in your Talos cluster!"
	@echo "Running cluster reset script..."
	@HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/reset_cluster.sh

.PHONY: talos-config
talos-config:
	@if [ -f $(TALOS_CONFIG_PATH) ]; then \
		mkdir -p ~/.talos; \
		cp $(TALOS_CONFIG_PATH) ~/.talos/config; \
		echo "Talos config copied to ~/.talos/config"; \
	else \
		echo "No talosconfig found at $(TALOS_CONFIG_PATH). Run 'make apply MODULE=talos' first."; \
	fi

.PHONY: talos-merge-kubeconfig
talos-merge-kubeconfig:
	@if [ ! -f $(KUBE_CONFIG_PATH) ]; then \
		echo "No kubeconfig found at $(KUBE_CONFIG_PATH). Run 'make talos-get-kubeconfig' first."; \
		exit 1; \
	fi
	@echo "Processing Talos kubeconfig..."
	@mkdir -p ~/.kube
	@if [ ! -f ~/.kube/config ]; then \
		echo "No existing kubeconfig found. Creating a new one."; \
		cp $(KUBE_CONFIG_PATH) ~/.kube/config; \
		echo "Kubeconfig copied to ~/.kube/config"; \
		echo "Current available contexts:"; \
		kubectl config get-contexts; \
	else \
		BACKUP=~/.kube/config.backup.$$(date +%Y%m%d%H%M%S); \
		echo "Creating backup of existing kubeconfig at $$BACKUP"; \
		cp ~/.kube/config $$BACKUP; \
		echo "Merging configurations..."; \
		KUBECONFIG=~/.kube/config:$(KUBE_CONFIG_PATH) kubectl config view --flatten > ~/.kube/config.merged; \
		mv ~/.kube/config.merged ~/.kube/config; \
		echo "Kubeconfig merged successfully."; \
		echo "Current available contexts:"; \
		kubectl config get-contexts; \
	fi

.PHONY: talos-ssh
talos-ssh:
	@if [ -z "$(NODE)" ]; then \
		echo "Usage: make talos-ssh NODE=<node_number>"; \
		echo "Example: make talos-ssh NODE=1"; \
		exit 1; \
	fi
	@IP=$$($(TOFU) -chdir=$(TF_PROJECT_ROOT) output -json talos_control_plane_ips | jq -r ".[$$(($${NODE}-1))]"); \
	if [ -n "$$IP" ]; then \
		echo "Connecting to control plane node $(NODE) ($$IP)..."; \
		ssh root@$$IP; \
	else \
		echo "Error: Node $(NODE) not found"; \
		exit 1; \
	fi

.PHONY: talos
talos:
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make talos CMD='command [args]' [TALOS_NODE_IP=<node-ip>]"; \
		echo "Example: make talos CMD='version'"; \
		echo "Example: make talos CMD='dashboard'"; \
		echo "Example: make talos CMD='upgrade' TALOS_NODE_IP=10.0.0.1"; \
		echo "Example: make talos CMD='logs kubelet' TALOS_NODE_IP=10.0.0.1"; \
		exit 1; \
	fi
	@if [ ! -f $(TALOS_CONFIG_PATH) ]; then \
		echo "No talosconfig found at $(TALOS_CONFIG_PATH). Run 'make apply MODULE=talos' first."; \
		exit 1; \
	fi
	@if [ -n "$(TALOS_NODE_IP)" ]; then \
		echo "Running talosctl $(CMD) on node $(TALOS_NODE_IP) using config at $(TALOS_CONFIG_PATH)"; \
		TALOSCONFIG=$(TALOS_CONFIG_PATH) $(TALOSCTL) -n $(TALOS_NODE_IP) -e $(TALOS_NODE_IP) $(CMD); \
	else \
		echo "Running talosctl $(CMD) using config at $(TALOS_CONFIG_PATH)"; \
		TALOSCONFIG=$(TALOS_CONFIG_PATH) $(TALOSCTL) $(CMD); \
	fi

.PHONY: talos-health
talos-health:
	@if [ ! -f $(TALOS_CONFIG_PATH) ]; then \
		echo "No talosconfig found at $(TALOS_CONFIG_PATH). Run 'make apply MODULE=talos' first."; \
		exit 1; \
	fi
	@echo "Checking Talos cluster health..."
	@TALOSCONFIG=$(TALOS_CONFIG_PATH) HCLOUD_TOKEN=$(HCLOUD_TOKEN) $(SCRIPTS_PATH)/talos_health.sh

talos-upgrade: ## Upgrade Talos cluster with custom image (TALOS_VERSION optional)
	@if [ ! -f "$(SCRIPTS_PATH)/generated/cluster_info.env" ]; then \
		echo "Error: cluster_info.env not found. Cluster must be configured first."; \
		exit 1; \
	fi
	@if [ ! -f $(TALOS_CONFIG_PATH) ]; then \
		echo "Error: talosconfig not found at $(TALOS_CONFIG_PATH). Cluster must be configured first."; \
		exit 1; \
	fi
	@echo "Upgrading Talos cluster with custom image..."
	@$(SCRIPTS_PATH)/upgrade_talos.sh $(TALOS_VERSION)

# Hetzner Cloud commands - ensure token is passed
.PHONY: hcloud
hcloud: ## Run Hetzner Cloud CLI commands
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make hcloud CMD='command [args]'"; \
		echo "Example: make hcloud CMD='server list'"; \
	else \
		HCLOUD_TOKEN=$(HCLOUD_TOKEN) hcloud $(CMD); \
	fi

# Cloudflare API Commands
# -----------------------

# Default parameters for Cloudflare API calls
ID_TYPE ?= accounts
ID ?=
ENDPOINT ?=
JQ_FILTER ?= .

# Common function for Cloudflare API calls
# Avoids repeating the API call code
define cf_curl
	curl -s "https://api.cloudflare.com/client/v4/$(1)/$(2)/$(3)" \
		-H "Authorization: Bearer $(API_TOKEN)" \
		-H "Content-Type: application/json"
endef

# Generic API call command
.PHONY: cf-api-call
cf-api-call: ## Make a custom Cloudflare API call
	@if [ -z "$(ENDPOINT)" ]; then \
		echo "Usage: make cf-api-call ENDPOINT=your/endpoint [ID_TYPE=accounts|zones] [ID=your_id] [JQ_FILTER=.]"; \
		echo "Example: make cf-api-call ENDPOINT=access/apps"; \
	else \
		_ID_TYPE=$(ID_TYPE); \
		if [ "$$_ID_TYPE" = "accounts" ]; then \
			_ID=$(if $(ID),$(ID),$(ACCOUNT_ID)); \
		elif [ "$$_ID_TYPE" = "zones" ]; then \
			_ID=$(if $(ID),$(ID),$(ZONE_ID)); \
		else \
			_ID=$(ID); \
		fi; \
		echo "Making API call to: $(ENDPOINT)"; \
		$(call cf_curl,$$_ID_TYPE,$$_ID,$(ENDPOINT)) | jq '$(JQ_FILTER)'; \
	fi

# Pattern rule for cf-* targets
cf-%:
	@_ID_TYPE=$(ID_TYPE); \
	if [ "$$_ID_TYPE" = "accounts" ]; then \
		_ID=$(if $(ID),$(ID),$(ACCOUNT_ID)); \
	elif [ "$$_ID_TYPE" = "zones" ]; then \
		_ID=$(if $(ID),$(ID),$(ZONE_ID)); \
	else \
		_ID=$(ID); \
	fi; \
	echo "Making API call to: $*"; \
	$(call cf_curl,$$_ID_TYPE,$$_ID,$*) | jq

# Predefined Cloudflare commands
# Use the common cf_curl function to avoid duplication
.PHONY: cf-list-zero-trust-apps
cf-list-zero-trust-apps: ## List Cloudflare Zero Trust applications
	@echo "Listing Zero Trust applications:"
	@$(call cf_curl,accounts,$(ACCOUNT_ID),access/apps) | jq

.PHONY: cf-list-dns-records
cf-list-dns-records: ## List Cloudflare DNS records
	@echo "Listing DNS records:"
	@$(call cf_curl,zones,$(ZONE_ID),dns_records) | jq

.PHONY: cf-list-policies
cf-list-policies: ## List policies for all Zero Trust apps
	@echo "Listing all Zero Trust applications with their policies:"
	@$(call cf_curl,accounts,$(ACCOUNT_ID),access/apps) | jq '.result[] | {app_name: .name, domain: .domain, policies: [.policies[] | {name, decision}]}'

# Auto-generated help system
.PHONY: help
help:
	@echo "Homelab Terraform Makefile"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Module targeting:"
	@echo "  make tf-plan MODULE=talos    - Target specific module"
	@echo "  make tf-apply MODULE=talos   - Target specific module"
	@echo "  make tf-output MODULE=talos  - Show outputs from specific module"
	@echo ""
	@echo "Auto-approve:"
	@echo "  make tf-apply AUTO_APPROVE=yes - Skip approval prompt"


# Vault command
.PHONY: vault
vault: ## Run Vault CLI commands
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make vault CMD='command [args]'"; \
		echo "Example: make vault CMD='kv list secret/data'"; \
	else \
		VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=$(VAULT_TOKEN) $(VAULT) $(CMD); \
	fi

# PostgreSQL command
.PHONY: psql
psql: ## Connect to PostgreSQL or run SQL commands
	@if [ -z "$(CMD)" ]; then \
		PG_PASSWORD=$$(VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=$(VAULT_TOKEN) $(VAULT) kv get -field=postgres-password kv/database/database/postgresql); \
		PGPASSWORD="$$PG_PASSWORD" /opt/homebrew/opt/libpq/bin/psql -h localhost -U postgres -p 5432; \
	else \
		PG_PASSWORD=$$(VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=$(VAULT_TOKEN) $(VAULT) kv get -field=postgres-password kv/database/database/postgresql); \
		PGPASSWORD="$$PG_PASSWORD" /opt/homebrew/opt/libpq/bin/psql -h localhost -U postgres -p 5432 -c "$(CMD)"; \
	fi

# ArgoCD commands
.PHONY: argocd-login
argocd-login: ## Log in to ArgoCD CLI using admin credentials
	@ARGOCD_PASSWORD=$$($(KUBECTL) get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d); \
	ARGOCD_ENDPOINT=$$($(KUBECTL) get httproute argocd-server -n argocd -o jsonpath="{.spec.hostnames[0]}"); \
	echo "ArgoCD Endpoint: http://$$ARGOCD_ENDPOINT"; \
	echo "Username: admin"; \
	echo "Password: $$ARGOCD_PASSWORD"; \
	echo ""; \
	echo "Logging in to ArgoCD CLI..."; \
	argocd login $$ARGOCD_ENDPOINT --username admin --password "$$ARGOCD_PASSWORD" --plaintext --insecure; \
	if [ $$? -eq 0 ]; then \
		echo "Successfully logged in to ArgoCD"; \
	else \
		echo "Failed to log in to ArgoCD CLI. You can still access the web UI with the credentials above."; \
	fi

.PHONY: argocd
argocd: ## Run ArgoCD CLI commands
	@if [ -z "$(CMD)" ]; then \
		echo "Usage: make argocd CMD='command [args]'"; \
		echo "Example: make argocd CMD='app list'"; \
	else \
		if [ ! -f ~/.argocd/config ]; then \
			$(MAKE) argocd-login; \
		fi; \
		argocd $(CMD) --port-forward --port-forward-namespace argocd --plaintext; \
	fi

# Cilium Gateway validation
.PHONY: validate-cilium-gateway
validate-cilium-gateway: ## Validate Cilium Gateway configuration
	@echo "Validating Cilium Gateway configuration..."
	@KUBECONFIG=$(KUBE_CONFIG_PATH) $(SCRIPTS_PATH)/validate-cilium-gateway.sh

# Default target
.DEFAULT_GOAL := help
