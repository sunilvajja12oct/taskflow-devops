# ADR 0007: Self-hosted Prometheus + Grafana, static scrape target, anonymous Grafana access

**Status:** Accepted

## Context

CloudWatch already covers instance-level health (`StatusCheckFailed` → SNS).
What it doesn't cover is application-level behavior — request rate, error
rate, latency — the metrics most job postings and real incidents actually
care about, and the stack (Prometheus + Grafana) most postings name by name.

## Decision

Run Prometheus and Grafana as plain Kubernetes manifests (not the
`kube-prometheus-stack` Helm chart) on the same k3s node as everything else:

- **App-level instrumentation**: `prom-client` in `app/src/app.js`, exposing
  `/metrics` with default Node.js metrics plus a custom
  `http_requests_total` counter and `http_request_duration_seconds`
  histogram, labeled by method/route/status.
- **Scraping**: Prometheus has one static target — the `taskflow` Service
  DNS name, not per-pod discovery via the Kubernetes API.
- **Grafana**: one pre-provisioned datasource + one dashboard (request rate,
  error rate, p95 latency, reachability), anonymous Viewer access enabled,
  exposed via a second Ingress host (`grafana.local`) on the same Traefik
  controller already in use.

## Consequences

- No new hourly AWS spend — both run as pods on the existing instance.
- Plain manifests instead of a chart dependency: every scrape config, alert
  rule, and dashboard panel is something written and understood directly,
  not inherited from a 40-chart dependency tree — more legible for an
  interview, easier to reason about for a project this size.
- **Static target instead of Kubernetes service discovery**: simpler (no
  RBAC needed for Prometheus to talk to the k8s API), but `up{job="taskflow-app"}`
  reflects the *Service's* reachability, not each pod individually — it can't
  tell you "1 of 2 replicas is down," only "the Service has zero working
  endpoints." Real per-pod visibility would need `kubernetes_sd_configs` and
  a ServiceAccount with `pods`/`endpoints` read access. Deferred as a
  reasonable next step, not something this pass needed.
- **Grafana anonymous Viewer access**: acceptable because nothing about this
  cluster is internet-facing — Traefik is only reachable from inside the VPC
  or via SSM on this one instance. This call would need revisiting the
  moment any ingress here becomes publicly reachable.
- **No Alertmanager → SNS bridge** (see [docs/runbooks/slos.md](../runbooks/slos.md)):
  alerts are real and visible in Prometheus's own UI, but don't yet page
  anyone. SNS's HTTP subscription handshake doesn't map cleanly onto
  Alertmanager's generic webhook receiver without extra glue code - scoped
  out rather than half-built.

## Alternatives considered

- **kube-prometheus-stack Helm chart** — the standard production choice, but
  a large dependency surface (CRDs, Alertmanager, node-exporter, kube-state-metrics)
  for a single-node dev cluster; rejected in favor of understanding every
  moving part directly.
- **CloudWatch Container Insights** — would avoid running Prometheus/Grafana
  at all, but doesn't teach the stack most job postings name, and this
  project's whole premise is hands-on depth over managed convenience (see
  [ADR 0002](0002-self-managed-k3s-over-eks.md)).
