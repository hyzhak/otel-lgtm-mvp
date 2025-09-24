#!/usr/bin/env bash
set -euo pipefail

KIND_BIN=${KIND:-kind}
KUBECTL_BIN=${KUBECTL:-kubectl}
DOCKER_BIN=${DOCKER:-docker}
CLUSTER_NAME=${CLUSTER_NAME:-otel-lgtm-dev}
OVERLAY_PATH=${OVERLAY_PATH:-deploy/k8s/overlays/local}
STACK_NAMESPACE=${NAMESPACE:-observability}
WAIT_DEPLOY_TIMEOUT=${WAIT_DEPLOY_TIMEOUT:-5m}
SKIP_BUILD=${SKIP_BUILD:-0}
SKIP_LOAD=${SKIP_LOAD:-0}
RESET_STACK=${RESET_STACK:-0}
DOCKER_CONFIG_DIR=${DOCKER_CONFIG_DIR:-}
KUBECONFIG_PATH=${KUBECONFIG_PATH:-}

if [[ -n "${DOCKER_CONFIG_DIR}" ]]; then
  export DOCKER_CONFIG="${DOCKER_CONFIG_DIR}"
fi

if [[ -n "${KUBECONFIG_PATH}" ]]; then
  mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
  export KUBECONFIG="${KUBECONFIG_PATH}"
fi

ensure_context() {
  if ! ${KIND_BIN} get clusters 2>/dev/null | grep -Fxq "${CLUSTER_NAME}"; then
    echo "[info] creating kind cluster ${CLUSTER_NAME}"
    ${KIND_BIN} create cluster --name "${CLUSTER_NAME}" --wait 2m
  else
    echo "[info] reusing existing kind cluster ${CLUSTER_NAME}"
  fi

  ${KIND_BIN} export kubeconfig --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
  ${KUBECTL_BIN} config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
}

build_images() {
  if [[ "${SKIP_BUILD}" == "1" ]]; then
    echo "[info] skipping image build"
    return
  fi

  ${DOCKER_BIN} build -t localhost/space-app:latest app
  ${DOCKER_BIN} build -t localhost/loadgen:latest loadgen
  ${DOCKER_BIN} build -t localhost/integration-tests:latest -f tests/integration/Dockerfile .
}

load_images() {
  if [[ "${SKIP_LOAD}" == "1" ]]; then
    echo "[info] skipping kind image load"
    return
  fi

  ${KIND_BIN} load docker-image localhost/space-app:latest --name "${CLUSTER_NAME}"
  ${KIND_BIN} load docker-image localhost/loadgen:latest --name "${CLUSTER_NAME}"
  ${KIND_BIN} load docker-image localhost/integration-tests:latest --name "${CLUSTER_NAME}"
}

deploy_stack() {
  if [[ "${RESET_STACK}" == "1" ]]; then
    echo "[info] removing existing deployment resources"
    ${KUBECTL_BIN} delete -k "${OVERLAY_PATH}" >/dev/null 2>&1 || true
  fi

  ${KUBECTL_BIN} apply -k "${OVERLAY_PATH}"

  ${KUBECTL_BIN} wait \
    --namespace "${STACK_NAMESPACE}" \
    --for=condition=Available deployment --all \
    --timeout="${WAIT_DEPLOY_TIMEOUT}"
}

summarise_access() {
  echo
  ${KUBECTL_BIN} get pods -n "${STACK_NAMESPACE}"
  ${KUBECTL_BIN} get svc -n "${STACK_NAMESPACE}"

  local active_kubeconfig="${KUBECONFIG:-$(printf '%s/.kube/config' "$HOME")}" 

  cat <<MSG

Stack is ready.
- Port-forward the FastAPI app:   kubectl port-forward -n ${STACK_NAMESPACE} svc/space-app 8000:8000
- Port-forward Grafana dashboards: kubectl port-forward -n ${STACK_NAMESPACE} svc/grafana 3000:3000

When finished, tear down the stack with:
  kubectl delete -k deploy/k8s/overlays/local
and optionally delete the kind cluster with: kind delete cluster --name ${CLUSTER_NAME}

Active kubeconfig: ${active_kubeconfig}
If you need to use it in a new shell run: export KUBECONFIG=${active_kubeconfig}
MSG
}

ensure_context
build_images
load_images
deploy_stack
summarise_access
