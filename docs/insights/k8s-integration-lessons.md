# Kubernetes Integration Lessons Learned

## Grafana provisioning paths
- **Issue:** Grafana started without any Prometheus, Loki, or Tempo data sources even though provisioning ConfigMaps were applied.
- **Resolution:** Explicitly mapped each provisioning file (`datasources.yml`, `dashboards.yml`, `alerts.yml`) into Grafana's expected subdirectories under `/etc/grafana/provisioning`. This mirrors the docker-compose volume layout and unblocks automatic data-source creation.
- **Takeaway:** When bridging compose-to-Kubernetes configs, verify mount paths against upstream defaults—Grafana silently skips provisioning if the directory structure is off.

## Tempo OTLP endpoints
- **Issue:** The Tempo distributor only listened on the service DNS name (`tempo:4317/4318`), which fails inside kind/Podman where the pod IP differs from the service hostname.
- **Resolution:** Bound the OTLP gRPC and HTTP listeners to `0.0.0.0` and exposed ports 4317/4318 on the Service. Now the OpenTelemetry Collector and integration tests can reach Tempo regardless of networking backend.
- **Takeaway:** Prefer binding to the pod IP (`0.0.0.0`) inside clusters unless a sidecar proxy injects routing—service hostnames are resolved by clients, not by the server.

## Self-contained integration test image
- **Issue:** The previous integration-test container assumed docker-compose volume mounts for test sources, so the Kubernetes Job could not run the suite.
- **Resolution:** Bundled `pytest.ini`, `tests/__init__.py`, and `tests/integration/` into the image, matching how the compose build works.
- **Takeaway:** Keep test containers hermetic. If a workflow mounts code at runtime, replicate that structure when reusing the image in other orchestrators.

## Local image names for kind
- **Issue:** kind requires images to be tagged `localhost/<name>` when loaded via `kind load docker-image`; our overlay still referenced upstream `ghcr.io` names, triggering pull failures.
- **Resolution:** Pointed the local overlay at `localhost/` tags and updated helper scripts to build/tag/load with that convention.
- **Takeaway:** Align overlay image names with the cluster loader tooling to avoid hidden pullFromRegistry steps, especially when iterating locally.

## Automation scripts
- **Issue:** Validating compose vs. Kubernetes flows manually was slow and error prone.
- **Resolution:** Added one-command bash helpers for compose tests, Kubernetes tests, and dev stack bootstrap. Each script supports overrides (`DOCKER_CONFIG_DIR`, timeouts, keep-flags) so they work on macOS and Ubuntu alike.
- **Takeaway:** Invest in repeatable scripts early; they surface configuration regressions (e.g., missing Tempo ports) before they hit CI or teammates.
