#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

report_dir="$(ensure_report_dir)"
export PERF_REPORT_DIR="$report_dir"

if [[ "${PERF_SKIP_ENV:-}" != "1" ]]; then
  write_env_metadata "$report_dir"
fi

(cd "$ROOT_DIR" && mix run perf/bench/kv_store_bench.exs)

if [[ "${PERF_SKIP_REPORT:-}" != "1" ]]; then
  write_summary "$report_dir"
fi

printf 'Microbench complete. Results in %s\n' "$report_dir"
