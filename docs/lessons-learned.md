# Lessons Learned and Replication Guide

This document distills the key lessons from the OpenTelemetry LGTM MVP and outlines a reproducible playbook for building a similar observability stack. Each section highlights actionable steps, rationale, and references to configuration or code artifacts that can be reused.

## 1. Start with Clear Telemetry Goals

1. Identify the critical user journeys or API flows that must be observable. For this MVP, the `/`, `/work`, and `/error` endpoints represent healthy, latent, and failure scenarios.【F:app/main.py†L66-L118】
2. Decide which signals (traces, metrics, logs) are necessary for each flow. Capturing all three provides correlation opportunities across the stack.
3. Document desired dashboards or alerts early; they guide instrumentation granularity.

## 2. Instrument the Application First

1. Configure a unified OpenTelemetry `Resource` so every signal shares service metadata. This enables Grafana to filter and correlate telemetry across backends.【F:app/main.py†L24-L41】
2. Initialize trace, metric, and log providers at application startup. Reuse OTLP exporters so the collector can act as the fan-out point.【F:app/main.py†L42-L118】
3. Apply framework-specific auto-instrumentation (`FastAPIInstrumentor`) and add minimal manual spans or events to cover business logic hotspots.【F:app/main.py†L60-L105】
4. Emit structured logs via the OpenTelemetry logging handler so span and trace IDs appear automatically in log records.【F:app/main.py†L70-L118】

**Tip:** Keep instrumentation code close to request handlers to simplify onboarding for new contributors.

## 3. Centralize Routing with an OpenTelemetry Collector

1. Deploy a collector with both HTTP and gRPC OTLP receivers to accommodate varied client libraries.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L1-L16】
2. Add lightweight processors—`memory_limiter`, `batch`, and `resource`—to stabilize throughput and enforce consistent metadata.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L10-L19】
3. Configure exporters for each backend: Prometheus for metrics, Tempo for traces, and Loki for logs.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L20-L38】
4. Expose the Prometheus exporter endpoint so scrapers can pull metrics without direct app access.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L20-L24】

**Lesson:** Keeping routing logic in the collector decouples application changes from backend integrations.

## 4. Use the LGTM Stack for Telemetry Storage

1. **Prometheus** stores metrics and powers Grafana dashboards; configure scrape jobs to target the collector rather than the app to consolidate metrics exposure.【F:deploy/k8s/base/config/prometheus/prometheus.yml†L1-L8】
2. **Tempo** ingests OTLP traces out of the box, simplifying Grafana data source configuration.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L26-L32】
3. **Loki** supports OTLP log ingestion, enabling trace-to-log pivots thanks to shared IDs in log payloads.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L32-L38】【F:app/main.py†L70-L118】
4. **Grafana** unifies visualization. Provision data sources and dashboards via configuration files for repeatable deployments (`deploy/k8s/base/config/grafana`).

**Reminder:** Persist Prometheus and Loki data with volumes in production to avoid telemetry gaps after restarts.

## 5. Maintain Environment Parity

1. Store canonical configuration (Grafana provisioning, collector pipelines, backend configs) under `deploy/k8s/base/config/` so both Compose and Kubernetes reuse the same artifacts.
2. Provide Compose files (`docker-compose.yml`) for local testing and Kustomize overlays (`deploy/k8s/overlays/*`) for clusters, ensuring each environment diverges only where necessary (e.g., resource limits, ingress, image pull policies).
3. Share environment variables (`.env`) to align credentials and service endpoints across deployments.【F:README.md†L52-L85】

**Outcome:** Developers can reproduce observability issues locally with confidence that production pipelines behave identically.

## 6. Automate Load Generation for Testing

1. Implement a lightweight traffic generator (see `loadgen/loadgen.py`) to simulate real workloads and edge cases (latency and errors).【F:loadgen/loadgen.py†L1-L25】
2. Run the load generator in CI or during manual testing to validate dashboards, alerts, and correlations end-to-end.
3. Capture synthetic trace IDs or request IDs in test logs to assert telemetry completeness when running automated checks.

## 7. Testing and Quality Gates

1. Keep application tests in `tests/` and run them as part of CI to ensure feature changes do not break primary routes.
2. Leverage `docker-compose.integration.yml` or the Kubernetes manifests to spin up ephemeral observability stacks for smoke tests.
3. Validate observability by querying Grafana panels, Loki log streams, and Tempo trace views after running the load generator. Treat any missing telemetry as a failing condition.

## 8. Operational Considerations

1. Harden Grafana credentials (`GF_SECURITY_*` settings) before exposing the stack beyond local environments.【F:README.md†L52-L85】
2. Size the collector and backends according to expected throughput; use the `memory_limiter` processor as a safeguard and monitor queue pressure metrics for tuning.
3. Monitor storage utilization for Prometheus and Loki; configure retention policies that align with compliance requirements.
4. Document on-call runbooks for investigating missing telemetry—e.g., checking collector logs, verifying exporter connectivity, and ensuring OTLP endpoints are reachable.

## 9. Extending the Pattern

1. Add new exporters (e.g., OpenSearch for logs, Jaeger for traces) by editing `otelcol-config.yml` without touching application code.【F:deploy/k8s/base/config/otel-collector/otelcol-config.yml†L1-L38】
2. Introduce service-level objectives by defining recording rules in Prometheus and alerting via Alertmanager.
3. Expand tracing depth with manual spans around database calls or external API integrations.
4. Consider tail-based sampling in the collector once trace volume grows beyond storage capacity.

## 10. Documentation and Knowledge Sharing

1. Maintain architecture diagrams and walkthroughs (see `docs/high-level-design.md`) so new teams understand how telemetry flows through the system.
2. Keep lessons learned current by updating this document after major changes or incidents.
3. Encourage contributions by linking to relevant files within the repository whenever guidance references code or configuration.

By following these lessons, teams can rapidly bootstrap an observability platform that remains testable, maintainable, and extensible as the application evolves.
