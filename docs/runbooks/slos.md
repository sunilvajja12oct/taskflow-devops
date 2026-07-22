# TaskFlow SLOs

Backed by real metrics: the app exposes `/metrics` (via `prom-client`),
scraped by `taskflow-prometheus` every 15s. Dashboards at the Grafana
ingress (`grafana.local`, anonymous Viewer access - see
[ADR 0007](../adrs/0007-self-hosted-prometheus-grafana.md)). Alert rules
live in `k8s/taskflow/templates/prometheus-configmap.yaml`'s `rules.yml`.

## SLO 1 — Availability

**Target: 99% of requests over any 5-minute window return a non-5xx status.**

- Error budget: 1% of requests may fail before this SLO is breached — roughly
  14 minutes of full downtime per day, or a much larger number of scattered
  errors under partial degradation.
- Alert: `TaskFlowHighErrorRate` fires when the 5xx ratio exceeds 1% for 2
  minutes straight (a `for: 2m` guard so a single blip doesn't page).
- Query: `sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`

## SLO 2 — Latency

**Target: p95 request latency stays under 500ms over any 5-minute window.**

- Error budget: up to 5% of requests may exceed 500ms before this is breached.
- Alert: `TaskFlowHighLatencyP95` fires when p95 exceeds 500ms for 2 minutes.
- Query: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))`
- In practice: TaskFlow's routes are simple single-table queries against a
  same-instance Postgres pod, so p95 should normally sit well under 50ms.
  500ms is a deliberately loose target for a project this size — the point
  is having a real, alertable number, not a tight one.

## SLO 3 — Reachability

**Target: Prometheus can always scrape the app.**

- Alert: `TaskFlowAppDown` fires when `up{job="taskflow-app"} == 0` for 1
  minute — this only trips when the Service has **no** healthy endpoints at
  all (both replicas down), since the scrape target is the Service, not
  individual pods. See ADR 0007 for why, and what per-pod scraping would take.

## What "burning the budget" means here

None of these alerts currently reach the ops SNS topic (`taskflow-dev-ops-alerts`)
— they're visible in Prometheus's own Alerts UI and the Grafana dashboard,
but Alertmanager → SNS routing was scoped out of this pass (SNS's HTTP
subscription handshake doesn't map cleanly onto Alertmanager's generic
webhook receiver without extra glue). If any of these SLOs matter enough to
page someone, wiring that bridge — or swapping Alertmanager's receiver for
something that speaks SNS/webhook natively — is the next step.
