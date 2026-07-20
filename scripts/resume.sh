#!/usr/bin/env bash
set -euo pipefail
PROFILE=taskflow
REGION=us-east-1

echo "Fetching instance IDs..."
APP_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-app-01" --profile $PROFILE --region $REGION --query "Reservations[].Instances[].InstanceId" --output text)
NAT_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-nat" --profile $PROFILE --region $REGION --query "Reservations[].Instances[].InstanceId" --output text)

echo "Starting NAT instance $NAT_ID..."
aws ec2 start-instances --instance-ids $NAT_ID --profile $PROFILE --region $REGION > /dev/null
echo "Starting app instance $APP_ID..."
aws ec2 start-instances --instance-ids $APP_ID --profile $PROFILE --region $REGION > /dev/null

echo "Waiting for both to report running..."
aws ec2 wait instance-running --instance-ids $NAT_ID $APP_ID --profile $PROFILE --region $REGION

echo "Waiting up to 2 min for SSM agent to check in on the app instance..."
for i in $(seq 1 12); do
  STATUS=$(aws ssm describe-instance-information --profile $PROFILE --region $REGION --query "InstanceInformationList[?InstanceId=='$APP_ID'].PingStatus" --output text)
  if [ "$STATUS" == "Online" ]; then
    echo "SSM online. Ready."
    exit 0
  fi
  sleep 10
done
echo "SSM not confirmed online yet - check scripts/status.sh in a minute."
