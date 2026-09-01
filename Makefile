# Makefile — the portability layer for this project.
#
# Every automation path drives these targets rather than reimplementing the
# commands: GitHub Actions for the public path, Tekton for OpenShift, and you
# on your laptop. If a build command is not in here, it will drift.
#
# Run `make` or `make help` for the target list.

.DEFAULT_GOAL := help

# Load .env if present. Copy dev/.env.example to .env to get started.
-include .env
export

# ── Configuration ───────────────────────────────────────────────────────────
IMAGE_NAME   ?= ghcr.io/ka1ne/ansible-ee
IMAGE_TAG    ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
IMAGE        := $(IMAGE_NAME):$(IMAGE_TAG)
EE_FILE      ?= ee/execution-environment.yml
EE_CONTEXT   ?= context
CONTAINER_RT ?= docker
NAMESPACE    ?= default
PYTHON       ?= python3
VENV         ?= .venv

# Prefer tools from .venv when it exists, otherwise fall back to PATH. This is
# what lets the same targets work locally and in CI without a venv.
VBIN            := $(if $(wildcard $(VENV)/bin),$(VENV)/bin/,)
ANSIBLE_BUILDER := $(VBIN)ansible-builder
ANSIBLE_LINT    := $(VBIN)ansible-lint
YAMLLINT        := $(VBIN)yamllint
ANSIBLE_PLAYBOOK:= $(VBIN)ansible-playbook

.PHONY: help bootstrap venv venv-clean check-prereqs \
        ee-build ee-context ee-push ee-shell \
        deps lint lint-yaml lint-ansible test-syntax test-local \
        awx-operator awx-install awx-status awx-check awx-apply \
        tekton-apply tekton-run clean

# ── Setup ───────────────────────────────────────────────────────────────────

check-prereqs: ## Verify git, a container runtime and Python 3.11+ are present
	@command -v git >/dev/null || { echo "ERROR: git not found"; exit 1; }
	@command -v $(CONTAINER_RT) >/dev/null || { echo "ERROR: $(CONTAINER_RT) not found (override with CONTAINER_RT=podman)"; exit 1; }
	@$(PYTHON) -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)' \
		|| { echo "ERROR: Python 3.11+ required (found $$($(PYTHON) --version))"; exit 1; }
	@echo "Prerequisites OK"

venv: ## Create .venv with the build and lint toolchain
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r requirements-dev.txt

venv-clean: ## Remove .venv
	rm -rf $(VENV)

bootstrap: check-prereqs venv ## First-time setup after cloning

# ── Execution Environment ───────────────────────────────────────────────────

ee-build: ## Build the EE image locally
	$(ANSIBLE_BUILDER) build \
		--file $(EE_FILE) \
		--context $(EE_CONTEXT) \
		--tag $(IMAGE) \
		--tag $(IMAGE_NAME):latest \
		--container-runtime $(CONTAINER_RT) \
		--verbosity 2

ee-context: ## Generate the build context and Containerfile without building
	$(ANSIBLE_BUILDER) create \
		--file $(EE_FILE) \
		--context $(EE_CONTEXT) \
		--output-filename Containerfile \
		--verbosity 2

ee-push: ## Push the EE image (expects a prior docker login)
	$(CONTAINER_RT) push $(IMAGE)
	$(CONTAINER_RT) push $(IMAGE_NAME):latest

ee-shell: ## Open a shell inside the built EE image
	$(CONTAINER_RT) run --rm -it --entrypoint /bin/bash $(IMAGE)

# ── Lint ────────────────────────────────────────────────────────────────────

deps: ## Install the collections needed to lint and run playbooks outside the EE
	$(VBIN)ansible-galaxy collection install -r ee/requirements.yml

lint: lint-yaml lint-ansible ## Run every linter

lint-yaml: ## yamllint across the repository
	$(YAMLLINT) -c .yamllint.yml .

lint-ansible: ## ansible-lint across playbooks and roles
	$(ANSIBLE_LINT) playbooks/ roles/

test-syntax: ## Syntax-check the playbooks
	$(ANSIBLE_PLAYBOOK) --syntax-check -i inventories/example/dev.yml playbooks/site.yml
	$(ANSIBLE_PLAYBOOK) --syntax-check -i inventories/example/dev.yml playbooks/connectivity_probe.yml

# ── Local development ───────────────────────────────────────────────────────

test-local: ## Run the connectivity probe locally (needs .env and a WinRM host)
	bash dev/scripts/run-local.sh $(ARGS)

# ── AWX ─────────────────────────────────────────────────────────────────────

AWX_OPERATOR_VERSION ?= 2.19.1
AWX_HOST             ?= http://localhost:30080

awx-operator: ## Install the AWX Operator onto the current cluster
	kubectl apply -k "github.com/ansible/awx-operator/config/default?ref=$(AWX_OPERATOR_VERSION)"
	kubectl -n awx wait deployment awx-operator-controller-manager \
		--for=condition=Available --timeout=180s

awx-install: awx-operator ## Deploy an AWX instance (run once, after awx-operator)
	kubectl apply -f awx/awx-instance.yml
	@echo "AWX is deploying — first run takes 3-5 minutes."
	@echo "Watch it with: kubectl get pods -n awx -w"

awx-status: ## Show AWX pods and the admin password
	kubectl get pods -n awx
	@echo ""
	@echo "URL: $(AWX_HOST)"
	@echo -n "Password: "
	@kubectl get secret awx-local-admin-password -n awx \
		-o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "not ready yet"
	@echo ""

awx-check: ## Preview the configuration-as-code changes (check mode)
	@echo "Not implemented yet — see #10"
	@exit 1

awx-apply: ## Apply the configuration-as-code to AWX
	@echo "Not implemented yet — see #10"
	@exit 1

# ── Tekton (OpenShift) ──────────────────────────────────────────────────────

tekton-apply: ## Apply the Tekton manifests
	kubectl apply -f ci/tekton/ -n $(NAMESPACE)

tekton-run: ## Trigger a PipelineRun (edit ci/tekton/pipelinerun.yml first)
	kubectl create -f ci/tekton/pipelinerun.yml -n $(NAMESPACE)

# ── Housekeeping ────────────────────────────────────────────────────────────

clean: ## Remove build artifacts and the locally built image
	rm -rf $(EE_CONTEXT) sbom-*.json
	-$(CONTAINER_RT) rmi $(IMAGE) $(IMAGE_NAME):latest 2>/dev/null

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
