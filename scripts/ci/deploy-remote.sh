#!/bin/bash
# Runs on the app instance via SSM, invoked by the `deploy` CI job.
# Expects ECR_REPO, IMAGE_TAG, AWS_REGION, CHART_BUCKET in the environment.
set -euo pipefail
: "${ECR_REPO:?}" "${IMAGE_TAG:?}" "${AWS_REGION:?}" "${CHART_BUCKET:?}"

for i in $(seq 1 30); do
  [ -f /opt/taskflow/bootstrap-complete ] && break
  sleep 10
done

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

kubectl create secret docker-registry ecr-pull-secret \
  --docker-server="$ECR_REPO" \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region "$AWS_REGION")" \
  --dry-run=client -o yaml | kubectl apply -f -

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id taskflow/dev/db-credentials --region "$AWS_REGION" \
  --query SecretString --output text)
DB_USER=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['username'])" "$SECRET_JSON")
DB_PASS=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['password'])" "$SECRET_JSON")

kubectl create secret generic taskflow-db \
  --from-literal=PGHOST=taskflow-postgres \
  --from-literal=PGPORT=5432 \
  --from-literal=PGUSER="$DB_USER" \
  --from-literal=PGPASSWORD="$DB_PASS" \
  --from-literal=PGDATABASE=taskflow \
  --dry-run=client -o yaml | kubectl apply -f -

cd /home/ec2-user/taskflow-chart
helm upgrade --install taskflow . \
  --set image.repository="$ECR_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --set backupBucket="$CHART_BUCKET"
