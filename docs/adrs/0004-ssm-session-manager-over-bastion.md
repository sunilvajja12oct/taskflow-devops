# ADR 0004: SSM Session Manager instead of a bastion host

**Status:** Accepted

## Context

Something needs to reach the private-subnet app instance for administration and
for CI/CD to run commands on it (`helm upgrade`, health checks). The classic
pattern is a bastion host in the public subnet with an open SSH port; the
current pattern most enterprises actually use is AWS Systems Manager Session
Manager, which needs no open inbound port and no host to patch.

## Decision

Use **SSM Session Manager** exclusively. The app instance's IAM role includes
`AmazonSSMManagedInstanceCore`; the private-instances security group
(`terraform/modules/network`) has **no inbound rules at all**. CI/CD talks to
the instance via `aws ssm send-command` (`AWS-RunShellScript`), not SSH.
Local/manual Ansible runs use `ansible_connection: ssh` tunneled through
`aws ssm start-session --document-name AWS-StartSSHSession` as the
`ProxyCommand`, so even that path never opens a port.

## Consequences

- No bastion host to provision, patch, or pay for — one fewer piece of
  always-on billable infrastructure.
- No SSH port ever open to the instance from the internet or even from within
  the VPC — the security group has zero inbound rules.
- All access is authenticated via IAM (the caller's AWS credentials/role) and
  logged in CloudTrail — better audit trail than SSH key possession.
- CI's `deploy`/`smoke-test`/`bootstrap` jobs all depend on the SSM agent being
  "Online" before anything else can happen — every one of those jobs has an
  explicit wait-for-online step, since there's no fallback path if SSM isn't up.

## Alternatives considered

- **Bastion host** — rejected: an always-on EC2 instance purely to forward SSH,
  plus the operational burden of hardening and patching it, for no benefit SSM
  doesn't already provide.
- **Public IP + security-group-restricted SSH** — rejected: still an open port,
  still a key to manage and rotate, and the private subnet's entire design
  point is "SSM-only access" (see the security group's own description in
  `terraform/modules/network`).
