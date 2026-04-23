.PHONY: build build-context scan scan-image scan-collections sbom lint lint-yaml \
        test-syntax test-dry-run \
        test-molecule-winrm test-molecule-winrm-converge \
        test-molecule-winrm-local test-molecule-winrm-local-converge _check-winrm-local-vars \
        test-molecule-init test-molecule-init-converge \
        test-molecule-mssql test-molecule-mssql-converge test-molecule-mssql-verify test-molecule-mssql-cleanup \
        _check-mssql-vars \
        awx-operator awx-install awx-status awx-sync-ee \
        push clean venv venv-clean bootstrap check-prereqs test-bootstrap help

# Load .env if present (copy .env.example → .env to get started)
-include .env
export

# --- Config ---
IMAGE_NAME    ?= ghcr.io/ka1ne/ansible-ee
IMAGE_TAG     ?= $(shell git rev-parse --short HEAD)
EE_FILE       ?= execution-environment.yml
CONTAINER_RT  ?= docker
VENV          ?= .venv
PYTHON        ?= python3
# WSL2: auto-detect Windows host IP from resolv.conf; override with WIN_HOST=<ip> make ...
WIN_HOST      ?= $(shell awk '/nameserver/{print $$2; exit}' /etc/resolv.conf)
WIN_USER      ?= Administrator

# --- Bootstrap ---
bootstrap: check-prereqs venv ## First-time setup after cloning: verify deps then create venv

check-prereqs: ## Verify system prerequisites (Python 3.11+, Podman, git)
	@command -v git      >/dev/null 2>&1 || (echo "ERROR: git not found"    && exit 1)
	@command -v podman   >/dev/null 2>&1 || (echo "ERROR: podman not found" && exit 1)
	@$(PYTHON) -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" \
		|| (echo "ERROR: Python 3.11+ required (found: $$($(PYTHON) --version))" && exit 1)
	@test -f .env || (echo "WARN: .env not found — copy .env.example to .env and fill in values"; true)
	@echo "Prerequisites OK"

test-bootstrap: ## Verify the venv is functional and all tooling is importable
	@test -d $(VENV) || (echo "ERROR: venv not found — run 'make bootstrap' first" && exit 1)
	@$(VENV)/bin/python -c "\
import importlib.metadata as m; \
pkgs = ['ansible-core','ansible-builder','ansible-navigator','molecule','pywinrm']; \
[print(f'{p:<24} {m.version(p)}') for p in pkgs]"
	@$(VENV)/bin/ansible-lint --version 2>&1 | head -1
	@$(VENV)/bin/ansible-lint --version >/dev/null 2>&1 \
		|| (echo "ERROR: ansible-lint failed — version conflict?" && $(VENV)/bin/ansible-lint --version && exit 1)
	@$(VENV)/bin/yamllint --version
	@echo "Bootstrap OK — all tools importable"

# --- Venv ---
venv: ## Create/update .venv with dev dependencies
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements-dev.txt

venv-clean: ## Remove the .venv directory
	rm -rf $(VENV)

# --- Build ---
build: ## Build the Execution Environment image
	$(VENV)/bin/ansible-builder build \
		--file $(EE_FILE) \
		--tag $(IMAGE_NAME):$(IMAGE_TAG) \
		--container-runtime $(CONTAINER_RT) \
		--verbosity 2

build-context: ## Generate Containerfile without building (inspect only)
	$(VENV)/bin/ansible-builder create \
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
	$(VENV)/bin/ansible-lint playbooks/ roles/ --strict

lint-yaml: ## YAML syntax check
	$(VENV)/bin/yamllint -c .yamllint.yml .

# --- Test ---
test-syntax: ## Syntax check all playbooks
	$(VENV)/bin/ansible-playbook playbooks/site.yml --syntax-check

test-dry-run: ## Dry run against dev inventory (no changes)
	$(VENV)/bin/ansible-playbook playbooks/site.yml \
		-i inventory/dev.yml \
		--check --diff \
		-e '{"capabilities": ["sqlserver"], "target_hosts": "windows", "env": "dev"}'

test-molecule-winrm: ## EE smoke test — spin up Windows 2019 container and verify WinRM ping through the EE image
	PATH=$(VENV)/bin:$$PATH EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(VENV)/bin/molecule test -s winrm-ping

test-molecule-winrm-converge: ## Converge only (no destroy) — useful when iterating on the EE image
	PATH=$(VENV)/bin:$$PATH EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(VENV)/bin/molecule converge -s winrm-ping

_check-winrm-local-vars:
	@test -n "$(WIN_HOST)"     || (echo "ERROR: WIN_HOST is required (auto-detect failed?)" && exit 1)
	@test -n "$(WIN_PASSWORD)" || (echo "ERROR: WIN_PASSWORD is required"                   && exit 1)

test-molecule-winrm-local: _check-winrm-local-vars ## WSL2 dev: win_ping through EE to Windows host (no VM — targets $(WIN_HOST))
	PATH=$(VENV)/bin:$$PATH \
		WIN_HOST=$(WIN_HOST) WIN_USER=$(WIN_USER) WIN_PASSWORD=$(WIN_PASSWORD) \
		EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(VENV)/bin/molecule test -s winrm-local

test-molecule-winrm-local-converge: _check-winrm-local-vars ## Converge only (no verify/reset)
	PATH=$(VENV)/bin:$$PATH \
		WIN_HOST=$(WIN_HOST) WIN_USER=$(WIN_USER) WIN_PASSWORD=$(WIN_PASSWORD) \
		EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(VENV)/bin/molecule converge -s winrm-local

test-molecule-init: ## Spin up Windows Server 2019 VM and verify WinRM ping via EE container
	cd roles/sqlserver_deploy && \
		PATH=$(abspath $(VENV))/bin:$$PATH \
		EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(abspath $(VENV))/bin/molecule test -s init

test-molecule-init-converge: ## Converge only — create VM and run ping (no destroy)
	cd roles/sqlserver_deploy && \
		PATH=$(abspath $(VENV))/bin:$$PATH \
		EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
		$(abspath $(VENV))/bin/molecule converge -s init

_check-mssql-vars:
	@test -n "$(MOLECULE_TEST_HOST)"     || (echo "ERROR: MOLECULE_TEST_HOST is required"     && exit 1)
	@test -n "$(ANSIBLE_WINRM_USER)"     || (echo "ERROR: ANSIBLE_WINRM_USER is required"     && exit 1)
	@test -n "$(ANSIBLE_WINRM_PASSWORD)" || (echo "ERROR: ANSIBLE_WINRM_PASSWORD is required" && exit 1)

_run-molecule-mssql:
	cd roles/sqlserver_deploy && \
		MOLECULE_TEST_HOST=$(MOLECULE_TEST_HOST) \
		ANSIBLE_WINRM_USER=$(ANSIBLE_WINRM_USER) \
		ANSIBLE_WINRM_PASSWORD=$(ANSIBLE_WINRM_PASSWORD) \
		$(VENV)/bin/molecule $(MOLECULE_CMD) -s mssql

test-molecule-mssql: _check-mssql-vars ## Full Molecule test of sqlserver_deploy against a live SQL Server host
	$(MAKE) _run-molecule-mssql MOLECULE_CMD=test

test-molecule-mssql-converge: _check-mssql-vars ## Converge only (no destroy) — useful during role development
	$(MAKE) _run-molecule-mssql MOLECULE_CMD=converge

test-molecule-mssql-verify: _check-mssql-vars ## Verify only — re-run assertions without re-converging
	$(MAKE) _run-molecule-mssql MOLECULE_CMD=verify

test-molecule-mssql-cleanup: _check-mssql-vars ## Cleanup test artefacts from SQL Server host
	$(MAKE) _run-molecule-mssql MOLECULE_CMD=cleanup

# --- AWX (local dev) ---
AWX_OPERATOR_VERSION ?= 2.19.1
AWX_HOST             ?= http://localhost:30080
AWX_TOKEN            ?=

awx-operator: ## Install AWX Operator onto the local k3s cluster
	kubectl apply -k "github.com/ansible/awx-operator/config/default?ref=$(AWX_OPERATOR_VERSION)"
	kubectl -n awx wait deployment awx-operator-controller-manager \
		--for=condition=Available --timeout=120s

awx-install: awx-operator ## Deploy AWX instance (run once after awx-operator)
	kubectl apply -f awx/awx-instance.yml
	@echo "AWX is deploying — this takes 3-5 min on first run."
	@echo "Watch progress: kubectl get pods -n awx -w"

awx-status: ## Show AWX pod status and print the access URL
	kubectl get pods -n awx
	@echo ""
	@echo "URL: $(AWX_HOST)"
	@echo "Password: $$(kubectl get secret awx-local-admin-password -n awx \
		-o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo 'not ready yet')"

awx-sync-ee: ## Register/update the EE in AWX (requires AWX_TOKEN in .env or env)
	@test -n "$(AWX_TOKEN)" || (echo "ERROR: AWX_TOKEN is required" && exit 1)
	AWX_HOST=$(AWX_HOST) \
	AWX_TOKEN=$(AWX_TOKEN) \
	EE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) \
	  bash awx/register-ee.sh

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
