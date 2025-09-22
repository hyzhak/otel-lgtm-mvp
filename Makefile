SHELL := /bin/bash
COMPOSE ?= docker compose
COMPOSE_FILES := -f docker-compose.yml -f docker-compose.integration.yml

.PHONY: integration-test
integration-test:
	@set -euo pipefail; \
	status=0; \
	$(COMPOSE) $(COMPOSE_FILES) up --build --exit-code-from integration-tests integration-tests || status=$$?; \
	$(COMPOSE) $(COMPOSE_FILES) down -v; \
	exit $$status

.PHONY: test
test: integration-test
