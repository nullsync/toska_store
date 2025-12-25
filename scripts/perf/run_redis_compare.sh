#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd redis-server
require_cmd redis-cli
require_cmd redis-benchmark
require_cmd curl

REDIS_PORT="${REDIS_PORT:-6379}"
TOSKA_HOST="${TOSKA_HOST:-127.0.0.1}"
TOSKA_PORT="${TOSKA_PORT:-4000}"
REQUESTS="${REQUESTS:-100000}"
CONCURRENCY="${CONCURRENCY:-50}"
VALUE_SIZE="${VALUE_SIZE:-128}"
KEY_SPACE="${KEY_SPACE:-10000}"
KEY_PREFIX="${KEY_PREFIX:-bench_}"

report_dir="$(ensure_report_dir)"
export PERF_REPORT_DIR="$report_dir"
write_env_metadata "$report_dir"

redis_dir="$(mktemp -d)"
redis_log="$report_dir/redis_server.log"
toska_log="$report_dir/toska_server.log"

redis_pid=""
toska_pid=""

cleanup() {
  if [[ -n "${toska_pid:-}" ]]; then
    kill "$toska_pid" >/dev/null 2>&1 || true
    wait "$toska_pid" 2>/dev/null || true
  fi

  if [[ -n "${redis_pid:-}" ]]; then
    kill "$redis_pid" >/dev/null 2>&1 || true
    wait "$redis_pid" 2>/dev/null || true
  fi

  rm -rf "$redis_dir"
}

trap cleanup EXIT

start_redis() {
  redis-server --port "$REDIS_PORT" --save "" --appendonly no --dir "$redis_dir" >"$redis_log" 2>&1 &
  redis_pid=$!

  for _ in $(seq 1 60); do
    if redis-cli -p "$REDIS_PORT" ping >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Redis did not start on port ${REDIS_PORT}." >&2
  exit 1
}

start_toska() {
  local expr
  expr=$(printf 'Toska.run(["start","--host","%s","--port","%s","--env","dev"])' "$TOSKA_HOST" "$TOSKA_PORT")
  (cd "$ROOT_DIR" && MIX_ENV=dev mix run -e "$expr") >"$toska_log" 2>&1 &
  toska_pid=$!

  for _ in $(seq 1 60); do
    if curl -s "http://${TOSKA_HOST}:${TOSKA_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Toska did not start on ${TOSKA_HOST}:${TOSKA_PORT}." >&2
  exit 1
}

start_redis
start_toska

redis_csv="$report_dir/redis_benchmark.csv"
redis-benchmark -h 127.0.0.1 -p "$REDIS_PORT" \
  -n "$REQUESTS" -c "$CONCURRENCY" -d "$VALUE_SIZE" -r "$KEY_SPACE" \
  -t set,get --csv >"$redis_csv"

read -r redis_set_ops redis_get_ops < <(
  python - <<PY
import csv
from pathlib import Path

rows = list(csv.reader(Path("${redis_csv}").read_text().splitlines()))
set_ops = 0.0
get_ops = 0.0
for row in rows:
    if not row or row[0] == "test":
        continue
    if row[0] == "SET":
        set_ops = float(row[1])
    if row[0] == "GET":
        get_ops = float(row[1])
print(f"{set_ops} {get_ops}")
PY
)

cat >"$report_dir/redis_benchmark.json" <<JSON
{
  "requests": ${REQUESTS},
  "concurrency": ${CONCURRENCY},
  "value_size": ${VALUE_SIZE},
  "key_space": ${KEY_SPACE},
  "set_ops_per_sec": ${redis_set_ops:-0},
  "get_ops_per_sec": ${redis_get_ops:-0}
}
JSON

toska_put_json="$report_dir/toska_put.json"
toska_get_json="$report_dir/toska_get.json"

TOSKA_HTTP_BENCH_MODE=put \
TOSKA_HTTP_BENCH_HOST="$TOSKA_HOST" \
TOSKA_HTTP_BENCH_PORT="$TOSKA_PORT" \
TOSKA_HTTP_BENCH_REQUESTS="$REQUESTS" \
TOSKA_HTTP_BENCH_CONCURRENCY="$CONCURRENCY" \
TOSKA_HTTP_BENCH_VALUE_SIZE="$VALUE_SIZE" \
TOSKA_HTTP_BENCH_KEY_SPACE="$KEY_SPACE" \
TOSKA_HTTP_BENCH_KEY_PREFIX="$KEY_PREFIX" \
TOSKA_HTTP_BENCH_OUTPUT="$toska_put_json" \
  mix run "$ROOT_DIR/scripts/perf/toska_http_bench.exs"

TOSKA_HTTP_BENCH_MODE=get \
TOSKA_HTTP_BENCH_HOST="$TOSKA_HOST" \
TOSKA_HTTP_BENCH_PORT="$TOSKA_PORT" \
TOSKA_HTTP_BENCH_REQUESTS="$REQUESTS" \
TOSKA_HTTP_BENCH_CONCURRENCY="$CONCURRENCY" \
TOSKA_HTTP_BENCH_VALUE_SIZE="$VALUE_SIZE" \
TOSKA_HTTP_BENCH_KEY_SPACE="$KEY_SPACE" \
TOSKA_HTTP_BENCH_KEY_PREFIX="$KEY_PREFIX" \
TOSKA_HTTP_BENCH_OUTPUT="$toska_get_json" \
  mix run "$ROOT_DIR/scripts/perf/toska_http_bench.exs"

python - <<PY
import json
from pathlib import Path

report_dir = Path("${report_dir}")

redis = json.loads((report_dir / "redis_benchmark.json").read_text())
toska_put = json.loads((report_dir / "toska_put.json").read_text())
toska_get = json.loads((report_dir / "toska_get.json").read_text())

compare = {
  "config": {
    "requests": ${REQUESTS},
    "concurrency": ${CONCURRENCY},
    "value_size": ${VALUE_SIZE},
    "key_space": ${KEY_SPACE}
  },
  "redis": redis,
  "toska": {
    "put": toska_put,
    "get": toska_get
  }
}

(report_dir / "redis_compare.json").write_text(json.dumps(compare, indent=2))

def fmt(value, digits=2):
    if value is None:
        return "n/a"
    return f"{value:.{digits}f}"

lines = []
lines.append("# Toska vs Redis comparison")
lines.append("")
lines.append(f"Requests: {redis['requests']}, Concurrency: {redis['concurrency']}, Value size: {redis['value_size']} bytes, Key space: {redis['key_space']}")
lines.append("")
lines.append("## Throughput (ops/sec)")
lines.append("")
lines.append("| Operation | Redis | Toska |")
lines.append("|---|---|---|")
lines.append(f"| SET/PUT | {fmt(redis['set_ops_per_sec'])} | {fmt(toska_put['ops_per_sec'])} |")
lines.append(f"| GET | {fmt(redis['get_ops_per_sec'])} | {fmt(toska_get['ops_per_sec'])} |")
lines.append("")
lines.append("## Toska latency (ms)")
lines.append("")
lines.append("| Operation | avg | p50 | p90 | p99 | errors |")
lines.append("|---|---|---|---|---|---|")
lines.append(f"| PUT | {fmt(toska_put['avg_ms'])} | {fmt(toska_put['p50_ms'])} | {fmt(toska_put['p90_ms'])} | {fmt(toska_put['p99_ms'])} | {toska_put['errors']} |")
lines.append(f"| GET | {fmt(toska_get['avg_ms'])} | {fmt(toska_get['p50_ms'])} | {fmt(toska_get['p90_ms'])} | {fmt(toska_get['p99_ms'])} | {toska_get['errors']} |")
lines.append("")
lines.append("Notes: Redis results come from redis-benchmark over RESP. Toska results use HTTP with the same request and concurrency counts.")

(report_dir / "redis_compare.md").write_text("\\n".join(lines))
PY

printf 'Redis comparison complete. Results in %s\n' "$report_dir"
