# Kubernetes Manifests Reference

This document explains how the manifests under `deploy/k8s/` assemble the OpenTelemetry demo stack, with links to the relevant official documentation for each Kubernetes feature that is used. If you are new to Kubernetes, use the linked resources to dive deeper into the concepts before modifying the manifests.

## Layout overview

| Path | Purpose | Key docs |
| ---- | ------- | -------- |
| `deploy/k8s/base/kustomization.yaml` | Defines the reusable base using [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/). | [Kustomize overview](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) |
| `deploy/k8s/base/*.yaml` | Deployments, Services, and PersistentVolumeClaims for Grafana, Loki, Tempo, Prometheus, the OpenTelemetry Collector, the FastAPI app, and the load generator. | [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [Services](https://kubernetes.io/docs/concepts/services-networking/service/), [PersistentVolumeClaims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims) |
| `deploy/k8s/base/config/` | Canonical configuration shared by docker-compose and Kubernetes ConfigMaps. | [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) |
| `deploy/k8s/overlays/local` | Development overlay that replaces container pull behaviour for locally built images. | [Image pull policy](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy) |
| `deploy/k8s/overlays/production` | Production-oriented overlay that adds storage classes, resource limits, LoadBalancer Services, and Ingress resources. | [Storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/), [Resource requests & limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/), [Services type LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer), [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) |

## Namespace

`deploy/k8s/base/namespace.yaml` creates the `observability` namespace and labels it with `app.kubernetes.io/part-of=otel-lgtm-mvp`. Namespaces logically separate workloads inside a cluster—see the [Namespaces documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) for more background.

## Configuration data

`deploy/k8s/base/kustomization.yaml` uses `configMapGenerator` to package the Grafana provisioning bundles, Prometheus scrape configuration, Loki configuration, Tempo configuration, and OpenTelemetry Collector pipeline from the shared `deploy/k8s/base/config/` directory. The `grafana-admin` Secret is created with `secretGenerator` so credentials can be overridden easily. Review:

- [ConfigMap design](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Secret management](https://kubernetes.io/docs/concepts/configuration/secret/)

The generated ConfigMaps are mounted read-only inside pods to prevent accidental drift from the source repository.

## Persistent storage

Four components persist state: Grafana dashboards, Loki data, Tempo data, and Prometheus time series. Each component declares a `PersistentVolumeClaim` with `ReadWriteOnce` access (suitable for single-node clusters) and a modest storage request. See the [PersistentVolume documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) for details on how the cluster satisfies these claims. Production overlays can override `storageClassName` to match the storage backend provided by your cloud or on-premises installation.

## Workloads and services

Each component is deployed via a `Deployment` and fronted by a `ClusterIP` Service for stable in-cluster discovery.

### Grafana (`deploy/k8s/base/grafana.yaml`)

- Deployment runs `grafana/grafana:12.1.1` with HTTP health probes (`/api/health`), referencing [container probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/).
- Mounts ConfigMaps for provisioning and dashboards as read-only volumes and attaches the `grafana-storage` PersistentVolumeClaim for stateful data.
- Environment variables mirror the docker-compose `.env` defaults. Credentials are sourced from the `grafana-admin` Secret.
- Exposes port `3000` via a ClusterIP Service. See [Service basics](https://kubernetes.io/docs/concepts/services-networking/service/#defining-a-service).

### Loki (`deploy/k8s/base/loki.yaml`)

- Single-replica Deployment using `grafana/loki:3.5.0` with ConfigMap-backed configuration and a PVC for object storage substitutes.
- The Service exposes Loki on port `3100`. Loki uses local filesystem storage, matching the compose demo; consult the [Loki documentation](https://grafana.com/docs/loki/latest/) when adjusting the config file under `deploy/k8s/base/config/loki/`.

### Tempo (`deploy/k8s/base/tempo.yaml`)

- Runs `grafana/tempo:2.8.2` with HTTP ingestion on port `3200` and persistent storage at `/var/tempo`.
- The metrics generator includes `external_labels` to tag exported metrics with `cluster: demo` so dashboards can distinguish environments.
- For configuration details, reference the [Tempo documentation](https://grafana.com/docs/tempo/latest/).

### Prometheus (`deploy/k8s/base/prometheus.yaml`)

- Deploys `prom/prometheus:v2.53.5` with a single scrape config aimed at the OpenTelemetry Collector and a one-day retention window.
- Stores data in the `prom-data` PVC.
- See the [Prometheus Helm chart values](https://prometheus.io/docs/prometheus/latest/getting_started/) and Kubernetes [Prometheus operator docs](https://github.com/prometheus-operator/prometheus-operator) for further tuning ideas.

### OpenTelemetry Collector (`deploy/k8s/base/otelcol.yaml`)

- Uses `otel/opentelemetry-collector-contrib:0.133.0` to receive OTLP traffic on gRPC/HTTP and expose Prometheus metrics on port `8889`.
- The configuration pulled from `deploy/k8s/base/config/otel-collector/otelcol-config.yml` matches the docker-compose example. Review the [OpenTelemetry Collector configuration guide](https://opentelemetry.io/docs/collector/configuration/) prior to editing pipelines.

### Demo application (`deploy/k8s/base/space-app.yaml`)

- Deployment references a published container image (`ghcr.io/hyzhak/otel-lgtm-mvp/space-app:latest`) by default, with probes hitting `/` to check health.
- Resource attributes define the service namespace/version, mirroring the compose stack. The local overlay swaps the imagePullPolicy to `Never` so locally built images can be used without pushing to a registry.

### Load generator (`deploy/k8s/base/loadgen.yaml`)

- Runs a slim Python container that continuously exercises the demo API. Resource requests keep CPU and memory footprint low.
- For resource sizing background, see [Managing Resources for Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

## Overlays

### Local overlay (`deploy/k8s/overlays/local`)

- Inherits the base resources and replaces `imagePullPolicy` with `Never` for the app and load generator, so you can build images locally and run them without a registry.
- The overlay also rewrites the image names to bare tags, matching the names used in `docker build` / `podman build` (configured via the `images` section of the kustomization file).

### Production overlay (`deploy/k8s/overlays/production`)

- Adds `storageClassName: gp3` (edit to match your storage provisioner) for all PVCs. See [Storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) to choose the correct value for your environment.
- Patches Deployments with resource requests/limits to aid scheduling and enforce quotas. Review the [requests and limits guide](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).
- Promotes Grafana to a `LoadBalancer` Service using AWS annotations as an example; adapt those annotations to your cloud provider (refer to the [Service type LoadBalancer](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer) documentation).
- `ingress.yaml` defines two Ingress resources with placeholder hostnames and TLS secrets. Replace them with your actual DNS names as documented in the [Ingress basics](https://kubernetes.io/docs/concepts/services-networking/ingress/) guide.

## Supporting configuration files

The files under `deploy/k8s/base/config/` are the canonical configuration shared by both deployment methods:

- Grafana provisioning (`deploy/k8s/base/config/grafana/provisioning/*`) – see the [Grafana provisioning reference](https://grafana.com/docs/grafana/latest/administration/provisioning/).
- Grafana dashboards (`deploy/k8s/base/config/grafana/dashboards/otel_mvp.json`).
- Loki configuration (`deploy/k8s/base/config/loki/loki-config.yml`) – consult the [Loki configuration reference](https://grafana.com/docs/loki/latest/configuration/).
- Tempo configuration (`deploy/k8s/base/config/tempo/tempo-config.yml`).
- Prometheus scrape config (`deploy/k8s/base/config/prometheus/prometheus.yml`) – refer to the [Prometheus configuration docs](https://prometheus.io/docs/prometheus/latest/configuration/configuration/).
- OpenTelemetry Collector pipeline (`deploy/k8s/base/config/otel-collector/otelcol-config.yml`).

Keeping these files in one place guarantees that the Kubernetes deployment and docker-compose stack share identical settings.

## Helper commands

The `Makefile` exposes the most common commands:

- `make k8s-apply-local` / `make k8s-delete-local`
- `make k8s-apply-production` / `make k8s-delete-production`
- `make k8s-integration-test`

For day-to-day development you can also run `./scripts/start_k8s_dev_stack.sh` to create a kind cluster, build/load the demo images, and apply the local overlay automatically.

Each target wraps the corresponding `kubectl apply -k` or `kubectl delete -k` command described in the [kustomize CLI reference](https://kubectl.docs.kubernetes.io/references/kustomize/kustomize/).

Use `kubectl kustomize deploy/k8s/overlays/<name>` to preview changes before applying them. When you modify service configuration files, update the copies under `deploy/k8s/base/config/` so both docker-compose and Kubernetes stay in sync.

## Integration tests inside Kubernetes

The docker-compose integration suite can run as a Kubernetes Job using the manifests in `deploy/k8s/tests/`:

1. Build the FastAPI app, load generator, and integration test images locally, then load them into your cluster (`kind load docker-image ...` for kind, `minikube image load ...` for Minikube, and so on).
2. Apply the desired overlay (for development the `local` overlay is recommended) and wait for all deployments to be available: `kubectl wait -n observability --for=condition=Available deployment --all --timeout=5m`.
3. Execute `make k8s-integration-test` to create the `integration-tests` Job. The helper script waits for completion, prints the test logs, and cleans up the Job automatically. Override `WAIT_TIMEOUT`, `NAMESPACE`, or `KUSTOMIZE_PATH` when invoking `scripts/run_k8s_integration_tests.sh` directly if you need custom behaviour.

The Job uses the same Python test image as the compose workflow, so failures point to configuration problems or readiness issues in the Kubernetes deployment rather than test drift.
