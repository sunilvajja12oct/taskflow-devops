# ADR 0003: cloud-init bootstrap instead of running Ansible from CI

**Status:** Accepted (supersedes the original plan of running the full
`ansible-playbook` from CI)

## Context

The original design had the `k3s`, `app-deploy`, `common-hardening`,
`cloudwatch-agent`, and `webserver` Ansible roles run against a fresh EC2
instance to get k3s, Helm, and the Helm chart in place. In practice, no
automation ever called `ansible-playbook` anywhere — not in CI, not in any
script. `user_data` only seeded an SSH key. This meant every fresh instance
needed a human to manually run the playbook before the CI/CD `deploy` job's
`helm upgrade` had anything to talk to — the pipeline could not actually recover
from an instance replacement on its own.

Wiring the *full* Ansible playbook into CI turned out to need real, sensitive
new setup: the SSH private key matching the instance's `authorized_keys`
(`ansible_connection: ssh` via an SSM `ProxyCommand`, per
`ansible/group_vars/role_webserver.yml`), the Ansible Vault password
(`common-hardening`'s `admin_notification_email` var is vault-encrypted), and
the `session-manager-plugin` binary on the runner. None of that was available
to hand a CI job without a person supplying new secrets.

## Decision

Split the responsibility:

- **k3s + Helm install** moved into EC2 `user_data` (`terraform/modules/compute`),
  so it runs automatically and unconditionally on first boot — no SSH key, no
  vault password, no CI dependency. Idempotent by construction (checks for the
  binaries before installing).
- **Helm chart delivery** moved to a CI `bootstrap` job that syncs
  `k8s/taskflow` to the S3 relay bucket that was already provisioned for this
  purpose (`ansible_transfer`), which the instance then pulls from during
  `deploy` — reusing the existing IAM instance role instead of adding SSH access
  for CI.
- Ansible's roles are **kept as-is** for everything not on this critical path —
  `common-hardening`, `cloudwatch-agent`, `webserver` — run manually, unchanged,
  whenever you want that layer applied. `k3s`/`app-deploy` still exist too, just
  no longer the thing that has to succeed for `deploy` to work.

## Consequences

- The pipeline can now recover from a full teardown (`destroy-all.sh` →
  `terraform apply`) without a human running a playbook — verified live: a
  from-scratch account went through `resolve → apply → bootstrap → build →
  deploy → smoke-test` with zero manual steps, twice.
- k3s/Helm install logic now exists in two places conceptually — the bash in
  `user_data` and the (currently unused for this purpose) Ansible `k3s` role —
  rather than one. Accepted trade-off for removing the SSH/vault dependency.
- This surfaced a real bug that a slower, Ansible-driven bootstrap likely
  wouldn't have hit as sharply: `user_data` runs within seconds of boot, before
  the NAT instance's route is reliably up, and a failed `curl | sh -` silently
  exits 0. See the [postmortem](../postmortems/0001-cold-boot-pipeline-failures.md)
  for the fix (retry on the binary's presence, not the pipe's exit code).

## Alternatives considered

- **Run the full playbook from CI** — rejected: needs new secrets (SSH private
  key, vault password) that weren't something to silently provision, and pulls
  in `session-manager-plugin` + `amazon.aws` collection setup on every CI run
  for roles (hardening, cloudwatch) that aren't actually blocking anything.
- **Do nothing, keep it manual** — rejected: this was the exact gap that made
  the CI/CD pipeline non-self-healing, which was the whole point of automating
  it in the first place.
