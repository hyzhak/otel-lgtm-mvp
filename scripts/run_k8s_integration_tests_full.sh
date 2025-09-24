#!/usr/bin/env bash
set -euo pipefail

KIND_BIN=${KIND:-kind}
KUBECTL_BIN=${KUBECTL:-kubectl}
DOCKER_BIN=${DOCKER:-docker}
CLUSTER_NAME=${CLUSTER_NAME:-otel-lgtm}
KEEP_CLUSTER=${KEEP_CLUSTER:-0}
KEEP_STACK=${KEEP_STACK:-0}
STACK_NAMESPACE=${NAMESPACE:-observability}
OVERLAY_PATH=${OVERLAY_PATH:-deploy/k8s/overlays/local}
WAIT_DEPLOY_TIMEOUT=${WAIT_DEPLOY_TIMEOUT:-5m}
WAIT_JOB_TIMEOUT=${WAIT_JOB_TIMEOUT:-15m}
DOCKER_CONFIG_DIR=${DOCKER_CONFIG_DIR:-}

if [[ -n "${DOCKER_CONFIG_DIR}" ]]; then
  export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"
fi

created_cluster=0
overlay_applied=0

cleanup() {
  if [[ "${overlay_applied}" == "1" ]] && [[ "${KEEP_STACK}" != "1" ]]; then
    ${KUBECTL_BIN} delete -k "${OVERLAY_PATH}" >/dev/null 2>&1 || true
  fi

  if [[ "${created_cluster}" == "1" ]] && [[ "${KEEP_CLUSTER}" != "1" ]]; then
    ${KIND_BIN} delete cluster --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if ! ${KIND_BIN} get clusters 2>/dev/null | grep -Fxq "${CLUSTER_NAME}"; then
  ${KIND_BIN} create cluster --name "${CLUSTER_NAME}" --wait 2m
  created_cluster=1
else
  echo "[info] kind cluster ${CLUSTER_NAME} already exists; reusing it"
fi

${DOCKER_BIN} build -t localhost/space-app:latest app
${DOCKER_BIN} build -t localhost/loadgen:latest loadgen
${DOCKER_BIN} build -t localhost/integration-tests:latest -f tests/integration/Dockerfile .

${KIND_BIN} load docker-image localhost/space-app:latest --name "${CLUSTER_NAME}"
${KIND_BIN} load docker-image localhost/loadgen:latest --name "${CLUSTER_NAME}"
${KIND_BIN} load docker-image localhost/integration-tests:latest --name "${CLUSTER_NAME}"

${KUBECTL_BIN} apply -k "${OVERLAY_PATH}"
overlay_applied=1

${KUBECTL_BIN} wait --namespace "${STACK_NAMESPACE}" --for=condition=Available deployment --all --timeout="${WAIT_DEPLOY_TIMEOUT}"

WAIT_TIMEOUT="${WAIT_JOB_TIMEOUT}" ./scripts/run_k8s_integration_tests.sh

if [[ "${KEEP_STACK}" != "1" ]]; then
  ${KUBECTL_BIN} delete -k "${OVERLAY_PATH}"
  overlay_applied=0
fi

if [[ "${created_cluster}" == "1" ]] && [[ "${KEEP_CLUSTER}" != "1" ]]; then
  ${KIND_BIN} delete cluster --name "${CLUSTER_NAME}"
  created_cluster=0
fi
