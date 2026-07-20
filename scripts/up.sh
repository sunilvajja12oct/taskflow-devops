#!/usr/bin/env bash
# Full "up": makes sure everything Terraform manages exists (in case
# anything was destroyed), then starts the two instances if stopped.
set -euo pipefail
cd "$(dirname "$0")/../terraform/envs/dev"
echo "Reconciling infrastructure..."
terraform apply -var-file=dev.tfvars -auto-approve
echo
"$(dirname "$0")/resume.sh"
