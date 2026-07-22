# Cost retrospective

Pulled from real AWS Cost Explorer and Budgets data on 2026-07-22, not
estimated.

## Actual spend to date

```
$ aws budgets describe-budget --budget-name taskflow-total-credit ...
BudgetLimit:   $130.00 (monthly, credit-style budget covering 2026-06-30 → 2026-12-31)
ActualSpend:   $0.00
HealthStatus:  HEALTHY
```

Daily `UnblendedCost` for 2026-07-15 → 2026-07-22 (the entire active build
window) is effectively zero — each day nets out to a few hundred-thousandths
of a cent, which is rounding/credit noise, not real usage:

```
2026-07-15   0.0000000002
2026-07-16  -0.0000000004
2026-07-17  -0.000000003
2026-07-18  -0.0000000001
2026-07-19  -0.0000000153
2026-07-20  -0.0000001456
2026-07-21  -0.0000001216
2026-07-22  -0.0000000776
```

Grouped by service for July, the only nonzero line item is `EC2 - Other` at
**$0.0007** — sub-cent. No RDS, no EKS, no NAT Gateway, no managed
Prometheus/Grafana line items exist, because none of those services are in
the architecture.

## Why spend is near zero, not just "budget wasn't exceeded"

This isn't luck — it's the direct, measurable result of decisions made and
recorded before any infrastructure existed:

- **NAT instance instead of NAT Gateway** ([ADR 0001](adrs/0001-nat-instance-over-nat-gateway.md)) —
  a NAT Gateway alone would run ~$32/month (~$0.045/hr + per-GB) whether or
  not anything used it. The `fck_nat` instance costs a t3.nano-class
  instance-hour, and is **free while stopped**.
- **Self-managed k3s instead of EKS** ([ADR 0002](adrs/0002-self-managed-k3s-over-eks.md)) —
  an EKS control plane is ~$0.10/hr (~$73/month) before a single pod runs.
  k3s folds the control plane into the app instance-hour already being paid
  for.
- **Self-hosted Postgres/Prometheus/Grafana instead of RDS/AMP/AMG** — each
  managed equivalent bills continuously regardless of idle time; running
  them as pods on the existing node adds no separate bill.
- **Pause discipline between sessions** (`scripts/pause.sh` /
  [pause-resume-destroy runbook](runbooks/pause-resume-destroy.md)) — the
  only two hourly-billed resources (app + NAT instances) get stopped between
  work sessions. VPC, IAM, ECR, Secrets Manager, and the k3s state on disk
  all survive and cost nothing while stopped.
- **EventBridge + Lambda auto-stop** (`terraform/modules/auto_stop`) — adds
  an automatic nightly safety net (06:00 UTC daily) on top of manual pause
  discipline, for the sessions where `pause.sh` doesn't get run by hand.
  Verified live on 2026-07-22: manually invoked the Lambda and confirmed both
  the app and NAT instances actually transitioned to `stopping`.

## What this would cost without those decisions

Rough on-demand `us-east-1` pricing, for scale — not what was actually spent:

| Component | This project | "Standard" managed equivalent | Approx. cost of the managed version |
|---|---|---|---|
| Kubernetes control plane | k3s on the app instance | EKS | ~$73/mo (control plane only) |
| Outbound NAT | `fck_nat` t3.nano instance | NAT Gateway | ~$32/mo + $0.045/GB |
| Database | Postgres pod on the app instance | RDS `db.t3.micro` | ~$12–15/mo |
| Metrics/dashboards | Prometheus+Grafana pods | AMP + AMG | usage-based, typically $20+/mo for a small setup |
| **Total (managed stack, idle)** | — | — | **~$140+/month before any real traffic** |

Two `t3.small` instances (app + NAT) run about $0.0208/hr each. Even left
running 24/7 for a full month with zero pause discipline, that's roughly
**$30/month** for compute — under a quarter of what the managed-service
equivalent costs just to exist. Actual spend so far is even lower than that,
since both instances have spent most of their life stopped between sessions.

## Budget headroom

At **$0.00 of $130.00** spent with the full platform (VPC, k3s, Postgres,
observability stack, backups, CI/CD, secret rotation, and now DR/load-testing
drills) already built and exercised, the remaining budget is effectively free
runway for further experimentation — the constraint that shaped every ADR in
this build never actually bound in practice, because the architecture was
chosen to make sure it wouldn't.
