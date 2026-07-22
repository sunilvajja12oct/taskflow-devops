# Runbook: Disaster recovery (Postgres backup & restore)

Related: [`backup-cronjob.yaml`](../../k8s/taskflow/templates/backup-cronjob.yaml).

## What's automated

- `taskflow-postgres-backup` CronJob runs daily at 08:00 UTC. It `pg_dump`s
  the `taskflow` database and uploads to
  `s3://<ansible_transfer bucket>/backups/taskflow-<UTC timestamp>.sql`.
- The bucket's `backups/` prefix keeps objects for 14 days
  (`terraform/modules/compute/main.tf`'s lifecycle rule); the unrelated
  `chart/` prefix still expires after 1 day.
- `successfulJobsHistoryLimit: 3` / `failedJobsHistoryLimit: 3` keep the last
  few Job objects around in k8s for log inspection.

## How to restore from a backup

1. Find the backup to restore:
   ```bash
   aws s3 ls s3://<bucket>/backups/ --profile taskflow --region us-east-1
   ```
2. Stream it directly into the running Postgres pod (no local temp file
   needed — the app instance already has the AWS CLI):
   ```bash
   export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
   aws s3 cp s3://<bucket>/backups/taskflow-<TIMESTAMP>.sql - --region us-east-1 \
     | kubectl exec -i deploy/taskflow-postgres -- psql -U taskflow_app -d taskflow
   ```
3. If the `tasks` table still exists (e.g. restoring onto a live, undamaged
   database rather than after a drop), `pg_dump`'s plain-SQL output will
   throw `relation "tasks" already exists` / `multiple primary keys` errors
   on the `CREATE TABLE` and constraint statements — these are expected and
   harmless. The dump still proceeds through `ALTER TABLE`, `COPY`, and
   `setval`, which is what actually restores the data. Confirm success by
   checking the app rather than the psql output:
   ```bash
   curl -s -H "Host: taskflow.local" http://localhost/tasks
   ```

## Manually triggering a backup (e.g. before a risky change, or to test the pipeline)

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl create job --from=cronjob/taskflow-postgres-backup manual-backup-$(date +%s)
kubectl wait --for=condition=complete job/manual-backup-<ts> --timeout=60s
kubectl logs job/manual-backup-<ts>
```

## Real restore drill — measured RTO/RPO (2026-07-22)

Run against the live dev environment, not simulated:

1. Seeded the app with a task (`dr-drill-marker`), triggered a manual backup
   job, and verified the resulting S3 object actually contained that row
   (`aws s3 cp ... - | grep`).
2. Created a **second** task (`post-backup-task-will-be-lost`) *after* that
   backup, to measure real data loss rather than a trivial zero.
3. Recorded a start time, then ran the destructive step:
   `kubectl exec deploy/taskflow-postgres -- psql -U taskflow_app -d taskflow -c "DROP TABLE tasks;"`.
   Confirmed the app broke (`HTTP 502` on `/tasks`).
4. Restored from the backup taken in step 1 (see procedure above).
5. Confirmed the app was serving correctly again.

**Results:**

| Metric | Measured | Notes |
|---|---|---|
| **RTO** | **~67 seconds** | Wall clock from `DROP TABLE` (21:10:10Z) to the app correctly serving restored data again (21:11:17Z). Almost all of this is the `aws s3 cp \| kubectl exec psql` pipeline itself — there's no manual decision-making step in the drill. |
| **RPO (measured)** | **~75 seconds** | Gap between the backup (21:08:55Z) and the simulated incident (21:10:10Z). The task created in that window (`post-backup-task-will-be-lost`) was confirmed gone after restore — proof the drill actually measured real data loss, not a no-op. |
| **RPO (worst case, production)** | **up to 24 hours** | The CronJob only runs once a day (`0 8 * * *`). A disaster striking right before the next scheduled run loses up to a full day of writes. If that's ever unacceptable, the fix is a shorter schedule, not a process change — this runbook's restore steps don't change. |

## Known gaps

- The backup only covers the `tasks` table's data — no point-in-time recovery
  (WAL archiving), so anything written between backups is unrecoverable by
  design, not just in the worst case above.
- This drill restored onto the *same* Postgres pod it was dumped from. Restoring
  onto a freshly recreated pod/PVC (e.g. after a real volume loss, not just a
  dropped table) has not been exercised — the mechanics should be identical
  (same `psql` restore command) but the surrounding wait-for-pod-ready timing
  hasn't been measured.
