.PHONY: build poc-local tekton-apply tekton-run clean help

IMAGE     ?= ansible-ee:poc
NAMESPACE ?= default
CR        ?= docker

build: ## Build the EE image locally
	$(CR) build -t $(IMAGE) .

poc-local: ## Run the PoC locally (requires poc/.env and WinRM set up on Windows host)
	bash poc/scripts/run-poc.sh

poc-local-skip-build: ## Run PoC using existing local image
	bash poc/scripts/run-poc.sh --skip-build

tekton-apply: ## Apply all Tekton manifests to the cluster
	kubectl apply -f tekton/ -n $(NAMESPACE)

tekton-run: ## Trigger a PipelineRun (edit tekton/pipelinerun.yml first)
	kubectl create -f tekton/pipelinerun.yml -n $(NAMESPACE)

clean: ## Remove local PoC containers and image
	podman rm -f mssql ansible-ee-poc 2>/dev/null || true
	podman network rm -f poc-net 2>/dev/null || true
	podman rmi $(IMAGE) 2>/dev/null || true

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'
