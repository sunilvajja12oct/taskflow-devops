#!/usr/bin/env bash
# Stops the app + NAT EC2 instances (the only hourly-billed resources in
# this stack). Everything else - VPC, IAM, ECR, Secrets Manager, k3s state
# on disk - costs nothing while stopped and survives untouched.
set -euo pipefail
PROFILE=taskflow
REGION=us-east-1
source "$(dirname "${BASH_SOURCE[0]}")/lib/report.sh"

pause_main() {
  echo "Fetching instance IDs..."
  APP_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-app-01" "Name=instance-state-name,Values=running" --profile $PROFILE --region $REGION --query "Reservations[].Instances[].InstanceId" --output text)
  NAT_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-nat" "Name=instance-state-name,Values=running" --profile $PROFILE --region $REGION --query "Reservations[].Instances[].InstanceId" --output text)

  if [ -z "$APP_ID" ] && [ -z "$NAT_ID" ]; then
    echo "Nothing running - already paused."
    return 0
  fi

  [ -n "$APP_ID" ] && echo "Stopping app instance $APP_ID..." && aws ec2 stop-instances --instance-ids $APP_ID --profile $PROFILE --region $REGION > /dev/null
  [ -n "$NAT_ID" ] && echo "Stopping NAT instance $NAT_ID..." && aws ec2 stop-instances --instance-ids $NAT_ID --profile $PROFILE --region $REGION > /dev/null

  echo "Stop requested. Billing for these two instances stops once they're fully stopped (~30-60s)."
  echo "Run scripts/status.sh to confirm."
}

report_run "pause" pause_main
