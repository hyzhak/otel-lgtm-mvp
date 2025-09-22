import pytest

from . import test_utils as utils


@pytest.fixture(scope="session", autouse=True)
def wait_for_stack() -> None:
    utils.wait_for_stack_ready()


@pytest.fixture(scope="module")
def telemetry_sample() -> None:
    utils.exercise_application()


@pytest.mark.integration
@pytest.mark.usefixtures("telemetry_sample")
def test_traces_ingested() -> None:
    utils.wait_until(
        lambda: utils.tempo_has_recent_traces(),
        utils.OBSERVABILITY_WAIT_TIMEOUT,
        f"Tempo never returned a trace for service.name={utils.SERVICE_NAME}",
    )


@pytest.mark.integration
@pytest.mark.usefixtures("telemetry_sample")
def test_metrics_ingested() -> None:
    utils.wait_until(
        lambda: utils.prometheus_has_metrics("app_requests_total"),
        utils.OBSERVABILITY_WAIT_TIMEOUT,
        "Prometheus never returned app_requests_total metrics",
    )


@pytest.mark.integration
@pytest.mark.usefixtures("telemetry_sample")
def test_logs_ingested() -> None:
    utils.wait_until(
        lambda: utils.loki_has_logs(),
        utils.OBSERVABILITY_WAIT_TIMEOUT,
        f"Loki never returned logs for {utils.LOKI_SERVICE_LABEL}={utils.SERVICE_NAME}",
    )
