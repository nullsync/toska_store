#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

perf_timestamp() {
  date -u "+%Y-%m-%dT%H-%M-%SZ"
}

ensure_report_dir() {
  local dir

  if [[ -n "${PERF_REPORT_DIR:-}" ]]; then
    dir="$PERF_REPORT_DIR"
  else
    dir="$ROOT_DIR/perf/reports/$(perf_timestamp)"
  fi

  mkdir -p "$dir"
  echo "$dir"
}

write_env_metadata() {
  local dir="$1"
  (cd "$ROOT_DIR" && PERF_REPORT_DIR="$dir" PERF_ENV_PATH="$dir/env.json" mix run scripts/perf/collect_env.exs)
}

write_summary() {
  local dir="$1"
  (cd "$ROOT_DIR" && PERF_REPORT_DIR="$dir" mix run scripts/perf/gen_report.exs)
}
