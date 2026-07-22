#!/usr/bin/env bash
# Full "up": makes sure everything Terraform manages exists (in case
# anything was destroyed), then starts the two instances if stopped.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../terraform/envs/dev"
echo "Reconciling infrastructure..."
terraform apply -var-file=dev.tfvars -auto-approve
echo
"$SCRIPT_DIR/resume.sh"
