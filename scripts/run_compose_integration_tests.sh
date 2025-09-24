#!/usr/bin/env bash
set -euo pipefail

DOCKER_CONFIG_DIR=${DOCKER_CONFIG_DIR:-}

if [[ -n "${DOCKER_CONFIG_DIR}" ]]; then
  export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"
fi

if [[ -n "${COMPOSE:-}" ]]; then
  IFS=' ' read -r -a COMPOSE_CMD <<< "${COMPOSE}"
else
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    echo "[error] neither 'docker compose' nor 'docker-compose' is available" >&2
    exit 1
  fi
fi

COMPOSE_ARGS=(-f docker-compose.yml -f docker-compose.integration.yml)

cleanup() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down -v >/dev/null 2>&1 || true
}

trap cleanup EXIT

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up --build --exit-code-from integration-tests integration-tests
