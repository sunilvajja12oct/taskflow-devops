# ADR 0002: Self-managed k3s instead of EKS

**Status:** Accepted

## Context

The app needs to run on Kubernetes. AWS EKS provides a managed control plane;
self-managed options (k3s, kubeadm) run the control plane on an EC2 instance we
own.

EKS's control plane costs ~$0.10/hr — about $73/month — before a single worker
node or pod exists. Against a $130 total credit, that's over half the entire
project budget spent on infrastructure that isn't itself something we get to
practice operating (it's managed specifically so you *don't* operate it).

## Decision

Run **k3s** (single control-plane node, also acting as the only worker) on the
existing app EC2 instance, installed automatically on first boot via
`user_data` — see [ADR 0003](0003-cloud-init-bootstrap-over-ansible-in-ci.md)
for how that install actually happens.

## Consequences

- Full control-plane cost is folded into the EC2 instance-hour we're already
  paying for the app server — no separate control-plane bill.
- We own etcd/control-plane operations ourselves, which k3s makes deliberately
  lightweight (single binary, embedded SQLite instead of etcd by default) —
  appropriate for a single-node learning cluster, not something to carry into a
  real multi-node production design without reconsidering.
- Single node means no real high-availability story for the control plane —
  acceptable here since the entire point is disposable, `terraform destroy`-able
  infrastructure, not uptime.
- The EKS stretch exercise from the original build plan (stand it up for one
  session, screenshot it, destroy same day) was never attempted — optional, no
  cost incurred either way.

## Alternatives considered

- **EKS** — rejected on cost for the reasons above; noted as a deliberate,
  time-boxed stretch exercise if ever revisited.
- **kubeadm** — a harder, more "real" path than k3s (manual control-plane
  component wiring, no batteries-included Traefik/servicelb). Rejected for now
  in favor of k3s's lower time cost, given the budget also has to cover
  Terraform, Ansible, CI/CD, and secrets work — not just Kubernetes.
