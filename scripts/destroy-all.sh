#!/usr/bin/env bash
# Full teardown - only run this when you're completely done with the
# project, not between work sessions (use pause.sh/resume.sh for that).
# This destroys the VPC, compute, secrets, registry, and CI role -
# everything Terraform manages. The S3 state bucket and DynamoDB lock
# table are NOT touched (they were created outside Terraform in Phase 0
# on purpose, so this script can still run).
set -euo pipefail
echo "This will DESTROY every AWS resource this project created."
echo "Type 'destroy everything' to confirm:"
read -r CONFIRM
if [ "$CONFIRM" != "destroy everything" ]; then
  echo "Aborted."
  exit 1
fi

cd "$(dirname "$0")/../terraform/envs/dev"
terraform destroy -var-file=dev.tfvars

echo "Done. State bucket taskflow-tfstate-* and DynamoDB taskflow-tf-locks"
echo "were left alone - delete those manually only if you're never coming back."
