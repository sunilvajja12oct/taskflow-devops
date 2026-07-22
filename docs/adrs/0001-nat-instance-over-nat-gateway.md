# ADR 0001: NAT instance instead of a managed NAT Gateway

**Status:** Accepted

## Context

Private-subnet resources (the app EC2 instance) need outbound internet access —
for SSM agent check-in, pulling k3s/Helm install scripts, and ECR image pulls —
without a public IP or open inbound ports. AWS offers two ways to do this: a
managed **NAT Gateway** or a self-managed **NAT instance**.

A NAT Gateway costs ~$0.045/hr plus ~$0.045/GB processed, before any actual
traffic — roughly $32/month just to exist, before a single byte moves through it.
Against a fixed $130 total credit for the whole project, that's a quarter of the
entire budget spent on a component we're not directly being graded on operating.

## Decision

Use a NAT **instance** (`terraform/modules/network`, via the `fck_nat` module — a
`t3.nano`-class instance running as an autoscaling group of 1) instead of a
managed NAT Gateway.

## Consequences

- Costs a small EC2 instance-hour instead of a managed-service hourly + per-GB
  fee — cheap enough to leave running for a full session without denting the
  budget, and free while stopped via `scripts/pause.sh`.
- We own patching/availability for the NAT path ourselves — a managed Gateway has
  no such burden. For a single-AZ learning project this is an acceptable
  trade, and understanding *why* NAT Gateway exists (and what you're paying for)
  is itself worth more here than using it.
- Discovered live during this build: the NAT instance and the app instance can be
  created in the same `terraform apply`, and the app instance's `user_data` can
  start running *before* the NAT instance has a working route. This caused a real,
  reproduced failure (see
  [the postmortem](../postmortems/0001-cold-boot-pipeline-failures.md)) that a
  managed NAT Gateway — provisioned near-instantly — would likely have avoided.
  Traded for the cost savings; the fix was a retry loop in `user_data`, not a
  NAT Gateway.

## Alternatives considered

- **NAT Gateway** — rejected on cost for a project this size and this duration.
- **No NAT, VPC endpoints only** — would cover ECR/S3/SSM traffic, but not the
  arbitrary `curl` calls in `user_data` (k3s/Helm install scripts, metrics-server
  manifest) without also mirroring those artifacts into S3 — more moving parts
  than the NAT instance for a project already juggling a lot.
