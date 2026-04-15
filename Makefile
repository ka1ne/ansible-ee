.PHONY: build scan test lint clean

# --- Config ---
IMAGE_NAME    ?= registry.internal.bank/ansible-ee
IMAGE_TAG     ?= $(shell git rev-parse --short HEAD)
EE_FILE       ?= execution-environment.yml
CONTAINER_RT  ?= podman

# --- Build ---
build: ## Build the Execution Environment image
	ansible-builder build \
		--file $(EE_FILE) \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		--container-runtime $(CONTAINER_RT) \
		--verbosity 2

build-context: ## Generate Containerfile without building (inspect only)
	ansible-builder create \
		--file $(EE_FILE) \
		--output-filename Containerfile

# --- Security ---
scan: scan-image scan-collections ## Run all security scans

scan-image: ## Trivy scan on built image
	trivy image \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--format table \
		$(IMAGE_NAME):$(IMAGE_TAG)

scan-collections: ## Scan Galaxy collection contents
	chmod +x scripts/scan-collections.sh
	./scripts/scan-collections.sh

sbom: ## Generate SBOM for built image
	syft $(IMAGE_NAME):$(IMAGE_TAG) \
		-o spdx-json \
		> sbom-$(IMAGE_TAG).spdx.json

# --- Lint ---
lint: ## Lint playbooks and roles
	ansible-lint playbooks/ roles/ --strict

lint-yaml: ## YAML syntax check
	yamllint -c .yamllint.yml .

# --- Test ---
test-syntax: ## Syntax check all playbooks
	ansible-playbook playbooks/site.yml --syntax-check

test-dry-run: ## Dry run against dev inventory (no changes)
	ansible-playbook playbooks/site.yml \
		-i inventory/dev.yml \
		--check --diff \
		-e '{"capabilities": ["iis"], "target_hosts": "windows", "env": "dev"}'

# --- Publish ---
push: ## Push image to internal registry
	$(CONTAINER_RT) push $(IMAGE_NAME):$(IMAGE_TAG)
	$(CONTAINER_RT) tag $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):latest
	$(CONTAINER_RT) push $(IMAGE_NAME):latest

# --- Clean ---
clean: ## Remove build artifacts
	rm -rf context/ sbom-*.json
	$(CONTAINER_RT) rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true

# --- Help ---
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
