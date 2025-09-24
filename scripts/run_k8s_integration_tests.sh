#!/usr/bin/env bash
set -euo pipefail

KUBECTL=${KUBECTL:-kubectl}
KUSTOMIZE_PATH=${KUSTOMIZE_PATH:-deploy/k8s/tests}
JOB_NAME=${JOB_NAME:-integration-tests}
NAMESPACE=${NAMESPACE:-observability}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-10m}
KEEP_RESOURCES=${KEEP_RESOURCES:-0}

cleanup() {
  if [[ "$KEEP_RESOURCES" != "1" ]]; then
    ${KUBECTL} delete -k "${KUSTOMIZE_PATH}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

get_latest_pod() {
  ${KUBECTL} get pods \
    --namespace "${NAMESPACE}" \
    --selector "job-name=${JOB_NAME}" \
    -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | sort \
    | awk 'END {print $2}'
}

${KUBECTL} delete job "${JOB_NAME}" --namespace "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
${KUBECTL} apply -k "${KUSTOMIZE_PATH}"

wait_cmd=("${KUBECTL}" wait --namespace "${NAMESPACE}" --for=condition=complete "job/${JOB_NAME}" --timeout="${WAIT_TIMEOUT}")
if ! "${wait_cmd[@]}"; then
  echo "[error] integration test job did not complete successfully" >&2
  ${KUBECTL} get pods --namespace "${NAMESPACE}" --selector "job-name=${JOB_NAME}" || true
  ${KUBECTL} describe job "${JOB_NAME}" --namespace "${NAMESPACE}" || true
  latest_pod=$(get_latest_pod || true)
  if [[ -n "${latest_pod:-}" ]]; then
    echo "--- logs from ${latest_pod} ---" >&2
    ${KUBECTL} logs "${latest_pod}" --namespace "${NAMESPACE}" || true
  fi
  KEEP_RESOURCES=1
  exit 1
fi

latest_pod=$(get_latest_pod || true)
if [[ -z "${latest_pod:-}" ]]; then
  echo "[warn] job completed but no pod was found for ${JOB_NAME}" >&2
else
  echo "--- logs from ${latest_pod} ---"
  ${KUBECTL} logs "${latest_pod}" --namespace "${NAMESPACE}"
fi
