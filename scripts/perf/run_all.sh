#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

report_dir="$(ensure_report_dir)"
export PERF_REPORT_DIR="$report_dir"

write_env_metadata "$report_dir"

PERF_SKIP_ENV=1 PERF_SKIP_REPORT=1 "$SCRIPT_DIR/run_microbench.sh"
PERF_SKIP_ENV=1 PERF_SKIP_REPORT=1 "$SCRIPT_DIR/run_replication_bench.sh"

if command -v k6 >/dev/null 2>&1; then
  PERF_SKIP_ENV=1 PERF_SKIP_REPORT=1 "$SCRIPT_DIR/run_k6.sh" kv
  PERF_SKIP_ENV=1 PERF_SKIP_REPORT=1 "$SCRIPT_DIR/run_k6.sh" replication
else
  echo "k6 not found; skipping HTTP load tests" >&2
fi

write_summary "$report_dir"

printf 'All performance tests complete. Results in %s\n' "$report_dir"
