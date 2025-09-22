from __future__ import annotations

import os
import time
from datetime import datetime, timedelta, timezone
from typing import Callable, Optional

import requests

STACK_READY_TIMEOUT = int(os.getenv("STACK_READY_TIMEOUT", "180"))
OBSERVABILITY_WAIT_TIMEOUT = int(os.getenv("OBS_WAIT_TIMEOUT", "120"))

GRAFANA_HEALTH = os.getenv("GRAFANA_HEALTH_URL", "http://grafana:3000/api/health")
LOKI_READY = os.getenv("LOKI_READY_URL", "http://loki:3100/ready")
TEMPO_READY = os.getenv("TEMPO_READY_URL", "http://tempo:3200/ready")
PROM_READY = os.getenv("PROM_READY_URL", "http://prometheus:9090/-/ready")
APP_ROOT = os.getenv("APP_BASE_URL", "http://space-app:8000")

TEMPO_SEARCH_URL = os.getenv("TEMPO_SEARCH_URL", "http://tempo:3200/api/search")
PROM_QUERY_URL = os.getenv("PROM_QUERY_URL", "http://prometheus:9090/api/v1/query")
LOKI_QUERY_RANGE_URL = os.getenv("LOKI_QUERY_RANGE_URL", "http://loki:3100/loki/api/v1/query_range")

PROM_EXPECTED_JOB = os.getenv("PROM_EXPECTED_JOB", "demo/space-app")


class StackError(RuntimeError):
    """Raised when the LGTM stack cannot be started or queried."""


def wait_for_stack_ready() -> None:
    checks = (
        ("Grafana", GRAFANA_HEALTH, lambda r: r.status_code == 200 and r.json().get("database") == "ok"),
        ("Loki", LOKI_READY, lambda r: r.status_code in (200, 204)),
        ("Tempo", TEMPO_READY, lambda r: r.status_code in (200, 204)),
        ("Prometheus", PROM_READY, lambda r: r.status_code == 200),
        ("Space App", f"{APP_ROOT}/", lambda r: r.status_code == 200),
    )

    for name, url, validator in checks:
        wait_until(lambda: check_http(url, validator), STACK_READY_TIMEOUT, f"{name} failed to become ready at {url}")


def wait_until(predicate: Callable[[], bool], timeout: int, message: str) -> None:
    deadline = time.monotonic() + timeout
    last_error: Optional[Exception] = None

    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except Exception as exc:  # pragma: no cover - diagnostic aid
            last_error = exc
        time.sleep(1)

    if last_error:
        raise StackError(f"{message}: last error {last_error}")
    raise StackError(message)


def check_http(url: str, validator: Callable[[requests.Response], bool]) -> bool:
    response = requests.get(url, timeout=5)
    return validator(response)


def exercise_application() -> None:
    with requests.Session() as session:
        for _ in range(3):
            response = session.get(APP_ROOT + "/", timeout=5)
            response.raise_for_status()

        work = session.get(APP_ROOT + "/work", params={"ms": 150}, timeout=5)
        work.raise_for_status()

        error = session.get(APP_ROOT + "/error", timeout=5)
        assert error.status_code == 500


def tempo_has_recent_traces() -> bool:
    window_end = datetime.now(timezone.utc)
    window_start = window_end - timedelta(minutes=5)
    payload = {
        "query": '{ service.name = "space-app" }',
        "start": window_start.isoformat(timespec="milliseconds"),
        "end": window_end.isoformat(timespec="milliseconds"),
        "limit": 5,
    }

    response = requests.post(
        TEMPO_SEARCH_URL,
        json=payload,
        timeout=10,
        headers={"Content-Type": "application/json"},
    )
    if response.status_code != 200:
        return False

    data = response.json()
    traces = data.get("traces") or data.get("data", {}).get("traces")
    return bool(traces)


def prometheus_has_metrics() -> bool:
    query = f'app_requests_total{{exported_job="{PROM_EXPECTED_JOB}"}}'
    response = requests.get(
        PROM_QUERY_URL,
        params={"query": query},
        timeout=10,
    )
    if response.status_code != 200:
        return False

    payload = response.json()
    if payload.get("status") != "success":
        return False

    results = payload.get("data", {}).get("result", [])
    if not results:
        return False

    try:
        return any(float(sample["value"][1]) >= 1 for sample in results)
    except (KeyError, ValueError, TypeError):
        return False


def loki_has_logs() -> bool:
    window_end = datetime.now(timezone.utc)
    window_start = window_end - timedelta(minutes=5)
    params = {
        "query": '{service_name="space-app"}',
        "start": str(int(window_start.timestamp() * 1e9)),
        "end": str(int(window_end.timestamp() * 1e9)),
        "limit": "20",
    }

    response = requests.get(
        LOKI_QUERY_RANGE_URL,
        params=params,
        timeout=10,
    )
    if response.status_code != 200:
        return False

    payload = response.json()
    if payload.get("status") != "success":
        return False

    results = payload.get("data", {}).get("result", [])
    return bool(results)
