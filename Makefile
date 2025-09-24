SHELL := /bin/bash
COMPOSE ?= docker compose
COMPOSE_FILES := -f docker-compose.yml -f docker-compose.integration.yml
KUBECTL ?= kubectl

.PHONY: integration-test
integration-test:
	@set -euo pipefail; \
	status=0; \
	$(COMPOSE) $(COMPOSE_FILES) up --build --exit-code-from integration-tests integration-tests || status=$$?; \
	$(COMPOSE) $(COMPOSE_FILES) down -v; \
	exit $$status

.PHONY: test
test: integration-test

.PHONY: k8s-apply-local
k8s-apply-local:
	$(KUBECTL) apply -k deploy/k8s/overlays/local

.PHONY: k8s-delete-local
k8s-delete-local:
	$(KUBECTL) delete -k deploy/k8s/overlays/local

.PHONY: k8s-apply-production
k8s-apply-production:
	$(KUBECTL) apply -k deploy/k8s/overlays/production

.PHONY: k8s-delete-production
k8s-delete-production:
	$(KUBECTL) delete -k deploy/k8s/overlays/production

.PHONY: k8s-integration-test
k8s-integration-test:
	./scripts/run_k8s_integration_tests.sh
