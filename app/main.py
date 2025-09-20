import asyncio
import logging
import os
import random
import time
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter

from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.trace import get_current_span, format_trace_id, format_span_id

SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "space-app")
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "1.0.0")
OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

resource = Resource.create(
    {
        "service.name": SERVICE_NAME,
        "service.version": SERVICE_VERSION,
        "service.namespace": os.getenv("SERVICE_NAMESPACE", "demo"),
    }
)

# ---- Traces ----
tracer_provider = TracerProvider(resource=resource)
tracer_provider.add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{OTLP_ENDPOINT}/v1/traces"))
)
tracer_provider.add_span_processor(BatchSpanProcessor(ConsoleSpanExporter()))
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)

# ---- Metrics ----
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=f"{OTLP_ENDPOINT}/v1/metrics")
)
meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)
meter = metrics.get_meter(__name__)

req_counter = meter.create_counter("app_requests_total", description="Total requests")
err_counter = meter.create_counter(
    "app_request_errors_total", description="Total errors"
)
latency_hist = meter.create_histogram(
    "app_request_duration_ms", unit="ms", description="Request duration"
)

# ---- Logs ----
logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint=f"{OTLP_ENDPOINT}/v1/logs"))
)
logging.basicConfig(level=logging.INFO)
logging.getLogger("opentelemetry").setLevel(logging.DEBUG)
logging.getLogger("opentelemetry.exporter").setLevel(logging.DEBUG)
logging.getLogger().addHandler(LoggingHandler(logger_provider=logger_provider))
log = logging.getLogger("space-app")

app = FastAPI(title="Space App – OTel Demo")

FastAPIInstrumentor.instrument_app(app)


@app.get("/")
async def root():
    start = time.perf_counter()
    current = get_current_span()
    ctx = current.get_span_context()
    log.info(
        "current_span_context",
        extra={
            "current_trace": format_trace_id(ctx.trace_id),
            "current_span": format_span_id(ctx.span_id),
            "is_valid": ctx.is_valid,
        },
    )
    with tracer.start_as_current_span("root-handler") as span:
        span.set_attribute("endpoint", "/")
        log.info(
            "hello from space-app",
            extra={"trace_id": trace.format_trace_id(span.get_span_context().trace_id)},
        )
        body = {"ok": True, "msg": "Hello from space-app"}
    elapsed_ms = (time.perf_counter() - start) * 1000
    req_counter.add(1)
    latency_hist.record(elapsed_ms, {"route": "/"})
    return JSONResponse(body)


@app.get("/work")
async def work(ms: Optional[int] = 200):
    start = time.perf_counter()
    current = get_current_span()
    ctx = current.get_span_context()
    log.info(
        "current_span_context",
        extra={
            "current_trace": format_trace_id(ctx.trace_id),
            "current_span": format_span_id(ctx.span_id),
            "is_valid": ctx.is_valid,
        },
    )
    with tracer.start_as_current_span("compute") as span:
        span.set_attribute("endpoint", "/work")
        span.set_attribute("work.ms", ms)
        # simulate work without blocking the event loop
        await asyncio.sleep(max(0, ms) / 1000.0)
        if random.random() < 0.05:
            log.warning(
                "intermittent issue observed",
                extra={
                    "trace_id": trace.format_trace_id(span.get_span_context().trace_id)
                },
            )
    elapsed_ms = (time.perf_counter() - start) * 1000
    req_counter.add(1, {"route": "/work"})
    latency_hist.record(elapsed_ms, {"route": "/work"})
    return {"ok": True, "work_ms": ms, "latency_ms": round(elapsed_ms, 2)}


@app.get("/error")
async def error():
    current = get_current_span()
    ctx = current.get_span_context()
    log.info(
        "current_span_context",
        extra={
            "current_trace": format_trace_id(ctx.trace_id),
            "current_span": format_span_id(ctx.span_id),
            "is_valid": ctx.is_valid,
        },
    )
    with tracer.start_as_current_span("boom") as span:
        span.set_attribute("endpoint", "/error")
        err_counter.add(1, {"route": "/error"})
        log.error(
            "boom: user-triggered error",
            extra={"trace_id": trace.format_trace_id(span.get_span_context().trace_id)},
        )
        raise HTTPException(status_code=500, detail="boom")
