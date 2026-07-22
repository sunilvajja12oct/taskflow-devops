# Resume bullets & interview talk-tracks

Drawn from what was actually built and verified live in this repo — every
number below is a real measurement (git history, CloudWatch, Cost Explorer,
or a drill run against the live environment), not an estimate.

## Resume bullets

Pick 2-4 depending on space; they're written to stand alone.

- Designed and built a self-hosted Kubernetes platform on AWS (VPC, k3s,
  Postgres, Prometheus/Grafana, CI/CD) under a fixed $130 budget, coming in at
  **$0.00 actual spend** by replacing managed services (EKS, NAT Gateway, RDS,
  Amazon Managed Prometheus/Grafana) with self-hosted equivalents — a
  documented ~$140+/month savings at idle, before any traffic.
- Built a GitHub Actions CI/CD pipeline (OIDC, no static AWS keys) that plans
  and applies Terraform, builds/scans/pushes a distroless Docker image to ECR,
  and deploys via Helm to a self-managed k3s cluster — then found and fixed a
  bug where `terraform plan`'s exit code had been silently swallowed by
  `tee` since the pipeline's first commit, so the required PR check had never
  once posted a real plan.
- Ran a live disaster-recovery drill against a production-shaped Postgres
  deployment: seeded data, took a verified S3 backup, deliberately dropped the
  table, and restored — measuring a real **~67s RTO** and **~75s RPO**, then
  wrote the runbook from the actual drill rather than from theory.
- Implemented and load-tested Kubernetes HPA autoscaling with a live k6 test:
  sustained ~956 req/s against a 2-replica deployment, watched CPU utilization
  hit 401% of its 70% target, and confirmed the HPA scaled to its 4-replica
  max within 30 seconds — with 0% request failures throughout.
- Found and fixed a real IAM authorization gap in an EventBridge+Lambda
  cost-automation feature: an auto-stop Lambda scoped to a `Project` resource
  tag failed against an Auto Scaling Group-launched EC2 instance because ASG
  instances don't inherit the provider's `default_tags` — rewrote the policy
  condition around the `Name` tag both instances reliably carry, then verified
  the fix by manually invoking the Lambda and confirming both instances
  actually transitioned to `stopping`.
- Diagnosed a Kubernetes self-deadlock in production-realistic conditions: a
  Postgres pod's readiness probe inherited the app's `PGHOST` env var via a
  shared `envFrom`, causing `pg_isready` to check the pod's own Service instead
  of itself — a Service that only routes to pods already marked Ready. Fixed
  by scoping the container's env vars explicitly.

## Interview talk-tracks

Each is a real story with a concrete root cause — useful for "tell me about a
time you debugged something hard" or "tell me about a cost decision you made."

### 1. The CI check that never actually ran

**Situation:** A GitHub Actions pipeline had a required PR check,
`terraform-plan`, that had been green on every single PR since the pipeline
was written.

**Task:** Verify the pipeline was actually doing what it claimed, rather than
trusting the checkmark.

**Action:** Read the raw job log instead of the summary — `terraform plan
-out=tfplan | tee plan_output.txt` had no `pipefail`, so the step's exit code
was always `tee`'s (0), never `terraform plan`'s. The plan itself had been
erroring on *every* run, both push and PR, because `terraform-plan` never set
`TF_VAR_ssh_public_key_override` the way the `apply` job did, so a `file()`
fallback call always failed on the runner. The PR comment step had been
posting the same truncated error, right after a deprecation warning, on every
PR — nobody had scrolled far enough to notice the diff never appeared.

**Result:** Set the missing env var in `terraform-plan`, added `set -o
pipefail`. More importantly: this is why the habit of reading raw logs instead
of trusting green checkmarks matters — this same discipline caught a second,
unrelated bug the same session (a deploy/smoke-test job that only checked the
AWS API call succeeded, never the command's actual result).

### 2. A Postgres pod that couldn't become ready — because of itself

**Situation:** After a Helm upgrade, the Postgres pod sat at `0/1 Ready` for 7+
minutes with no self-recovery, blocking the rolling update (though the app
itself stayed available — Kubernetes correctly refused to scale down the old
ReplicaSet).

**Task:** Find the root cause live, not by guessing at YAML.

**Action:** Traced it to `envFrom: secretRef: taskflow-db` on the *Postgres*
container — the same secret block the *app* uses, which includes
`PGHOST=taskflow-postgres` (the Service name, meant for the app to reach
Postgres). `pg_isready` respects `PGHOST` automatically, so the readiness
probe running inside the Postgres pod was checking the Service — which only
routes to pods that are already Ready. A pod cannot become ready by asking its
own Service whether it's ready; structurally circular.

**Result:** Removed the shared `envFrom` from the Postgres container, since it
only needs three explicit vars it already had via `secretKeyRef`. Verified
live: pod reached `Running 1/1` immediately after.

### 3. Four bugs a code review would never have found

**Situation:** After a static review flagged the k3s bootstrap and
instance-lookup scripts as "fragile," fixing them on paper and shipping wasn't
enough to know they actually worked.

**Task:** Prove it — by destroying the entire environment and rebuilding it
from a genuinely empty AWS account, watching every step live.

**Action:** That single rebuild surfaced four real bugs invisible to code
review, because each only exists at the intersection of timing, AWS API
behavior, and cold-start state: a `curl | sh` k3s install that raced the NAT
instance's route and failed silently (empty pipe, `sh -` exits 0 anyway); a
deploy/smoke-test pipeline that only checked the AWS API call succeeded, never
the command's actual result; a missing ECR pull secret nothing had ever
created; and an S3 bucket without `force_destroy` blocking teardown.

**Result:** All four fixed and re-verified by tearing the environment down and
rebuilding it *again*, this time clean end-to-end — the same discipline
applied a third time this project, later, when a torn-down environment needed
recreating for a DR drill and hit yet another real bug (see #5 below).

### 4. Making the "under budget" claim actually true

**Situation:** The project had a hard $130 credit ceiling. Anyone can promise
to "stay under budget" — the interesting engineering question is what
architecture choices make that true by construction instead of by discipline
alone.

**Task:** Choose a Kubernetes + database + observability + NAT architecture
that couldn't blow the budget even under a mistake.

**Action:** Every managed-service alternative was priced out before being
rejected: EKS's control plane alone runs ~$0.10/hr (~$73/month) before a
single pod exists — replaced with k3s folded into the app instance already
being paid for. A NAT Gateway runs ~$32/month to exist at all, before a byte
moves through it — replaced with a self-managed NAT instance, ~$0.02/hr and
free while stopped. RDS and Amazon Managed Prometheus/Grafana were replaced
with self-hosted pods on the same node, for the same reason.

**Result:** Pulled real AWS Cost Explorer data at the end of the build: actual
spend across the entire project is **$0.00** of the $130 budget — not an
estimate, the literal `ActualSpend` field from `aws budgets describe-budget`.
Backed by a second layer of automatic cost control added later: an
EventBridge-scheduled Lambda that stops both billed instances nightly, on top
of manual pause discipline between sessions.

### 5. A live DR drill, including the restore's own rough edges

**Situation:** A daily pg_dump-to-S3 backup CronJob existed and had been
verified to run — but "the backup runs" and "the restore actually works, and
you know how long it takes" are different claims.

**Task:** Prove the second claim with a real, timed drill — not a tabletop
exercise.

**Action:** Seeded a task, took a verified backup (confirmed the row was
actually inside the uploaded S3 object, not just that a file existed), then
created a *second* task after that backup specifically so the drill would
measure real data loss instead of a trivial zero. Recorded a start time,
dropped the `tasks` table live, confirmed the app broke (`HTTP 502`), then
restored by streaming the S3 object through `psql` via `kubectl exec`. Along
the way, hit and documented a real quirk: restoring a plain-SQL dump onto a
database whose app had already recreated an empty `tasks` table via its own
startup migration throws `relation already exists` errors on the `CREATE
TABLE`/constraint statements — expected and harmless, since the `COPY` and
`setval` statements that actually matter still succeed.

**Result:** Measured **~67s RTO** (drop → app correctly serving again) and
**~75s RPO** (backup → incident), with the pre-backup task surviving and the
post-backup task correctly gone — proof the numbers reflect a real restore,
not a no-op. Also flagged, rather than hid, what the drill didn't cover: this
restored onto the *same* pod it was dumped from, not a freshly recreated
pod/PVC after real volume loss.

### 6. Finding a live IAM gap by actually invoking the Lambda

**Situation:** Added an EventBridge-scheduled Lambda to stop the app and NAT
EC2 instances off-hours, with an IAM policy scoped to `aws:ResourceTag/Project`
so it couldn't touch anything outside this project.

**Task:** Don't just trust `terraform apply` succeeding — prove the Lambda's
actual job (stopping both instances) works, since a scheduled trigger that
silently fails is worse than no automation at all.

**Action:** Manually invoked the Lambda instead of waiting for its nightly
schedule. It failed on exactly one of the two instances:
`UnauthorizedOperation` on the NAT instance specifically. Root cause: the NAT
instance is launched by an Auto Scaling Group (via the `fck_nat` module), and
ASG-launched instances don't inherit the Terraform AWS provider's
`default_tags` the way directly-managed resources do — so the NAT instance
only ever had a bare `Name` tag, never `Project`.

**Result:** Rewrote the IAM condition around `aws:ResourceTag/Name` (matching
both instances' known names) instead of `Project`, applied, and re-invoked —
confirmed both instances actually transitioned to `stopping` this time. The
broader lesson: a scoped IAM policy that "should" work per the Terraform plan
still needs a real invocation to prove it, because tag propagation differs
between resource types Terraform manages directly and resources managed
indirectly through an ASG/launch template.
