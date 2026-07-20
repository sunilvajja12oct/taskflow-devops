#!/usr/bin/env bash
# Shared helper so every ops script leaves a timestamped report file under
# reports/, instead of only printing to the terminal.
#
# Usage (from a script that already has `set -euo pipefail`):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/report.sh"
#   my_main() { ... existing script body ... }
#   report_run "pause" my_main

REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/reports"

report_run() {
  local action="$1"
  local fn="$2"
  mkdir -p "$REPORT_DIR"
  local report_file
  report_file="$REPORT_DIR/${action}-$(date -u +%Y%m%dT%H%M%SZ).log"

  # Run with -e relaxed so a failure inside the pipeline doesn't skip the
  # status capture and footer below (set -e + pipefail would otherwise abort
  # the script the instant the pipeline reports non-zero).
  set +e
  {
    echo "===== $action - $(date -u +'%Y-%m-%d %H:%M:%S UTC') ====="
    echo
    "$fn"
  } 2>&1 | tee -a "$report_file"
  local status=${PIPESTATUS[0]}
  set -e

  {
    echo
    if [ "$status" -eq 0 ]; then
      echo "===== $action: SUCCESS ====="
    else
      echo "===== $action: FAILED (exit $status) ====="
    fi
  } | tee -a "$report_file"
  echo "Report saved to: $report_file"

  return "$status"
}
