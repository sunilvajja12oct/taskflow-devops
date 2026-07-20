#!/usr/bin/env bash
set -uo pipefail
PROFILE=taskflow
REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text 2>/dev/null)

line() { echo "----------------------------------------"; }

echo "===== TaskFlow Status Report ====="
echo "Account: $ACCOUNT_ID | Region: $REGION | $(date)"
line

echo "[Phase 0] Cost & Guardrails"
aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name taskflow-total-credit --profile $PROFILE --region us-east-1 \
  --query "Budget.[BudgetLimit.Amount,CalculatedSpend.ActualSpend.Amount]" --output text 2>/dev/null \
  | awk '{print "  Budget: $"$1" limit, $"$2" spent so far"}'
line

echo "[Phase 1] Network"
aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-nat" --profile $PROFILE --region $REGION \
  --query "Reservations[].Instances[].State.Name" --output text | xargs -I{} echo "  NAT instance: {}"
line

echo "[Phase 2] Compute"
APP_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-app-01" --profile $PROFILE --region $REGION \
  --query "Reservations[].Instances[].InstanceId" --output text)
APP_STATE=$(aws ec2 describe-instances --instance-ids "$APP_ID" --profile $PROFILE --region $REGION \
  --query "Reservations[].Instances[].State.Name" --output text 2>/dev/null)
echo "  App instance ($APP_ID): $APP_STATE"
aws ssm describe-instance-information --profile $PROFILE --region $REGION \
  --query "InstanceInformationList[?InstanceId=='$APP_ID'].PingStatus" --output text 2>/dev/null \
  | xargs -I{} echo "  SSM status: {}"
line

echo "[Phase 3] Secrets"
aws secretsmanager describe-secret --secret-id taskflow/dev/db-credentials --profile $PROFILE --region $REGION \
  --query "[Name,RotationEnabled]" --output text 2>/dev/null | awk '{print "  Secret "$1": rotation enabled="$2}'
line

echo "[Phase 4] Observability"
aws cloudwatch describe-alarms --alarm-names taskflow-dev-app-status-check-failed --profile $PROFILE --region $REGION \
  --query "MetricAlarms[].StateValue" --output text 2>/dev/null | xargs -I{} echo "  Status alarm: {}"
line

echo "[Phase 5] Container Registry"
aws ecr describe-repositories --repository-names taskflow-dev --profile $PROFILE --region $REGION \
  --query "repositories[].repositoryUri" --output text 2>/dev/null | xargs -I{} echo "  Repo: {}"
aws ecr list-images --repository-name taskflow-dev --profile $PROFILE --region $REGION \
  --query "length(imageIds)" --output text 2>/dev/null | xargs -I{} echo "  Images stored: {}"
line

echo "[Phase 6] Kubernetes (k3s)"
if [ "$APP_STATE" == "running" ]; then
  CMD_ID=$(aws ssm send-command --instance-ids "$APP_ID" --document-name "AWS-RunShellScript" \
    --parameters 'commands=["export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -o wide --no-headers"]' \
    --profile $PROFILE --region $REGION --query "Command.CommandId" --output text 2>/dev/null)
  sleep 4
  OUT=$(aws ssm get-command-invocation --instance-id "$APP_ID" --command-id "$CMD_ID" --profile $PROFILE --region $REGION \
    --query "StandardOutputContent" --output text 2>/dev/null)
  echo "$OUT" | sed 's/^/  /'
else
  echo "  App instance not running - skipped (run scripts/resume.sh first)"
fi
line

echo "[Phase 7] CI/CD - last 3 runs"
gh run list --limit 3 2>/dev/null | sed 's/^/  /'
line
echo "===== End of report ====="
