#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "$SCRIPT_DIR/_common.sh"

extract_host() {
  local url="$1"
  local stripped="${url#http://}"
  stripped="${stripped#https://}"
  local hostport="${stripped%%/*}"
  printf '%s' "${hostport%%:*}"
}

extract_port() {
  local url="$1"
  local host="$2"
  local stripped="${url#http://}"
  stripped="${stripped#https://}"
  local hostport="${stripped%%/*}"
  local port="${hostport##*:}"
  if [[ "$hostport" == "$host" ]]; then
    if [[ "$host" == "localhost" || "$host" == "127.0.0.1" || "$host" == "0.0.0.0" ]]; then
      port="4000"
    elif [[ "$url" == https://* ]]; then
      port="443"
    else
      port="80"
    fi
  fi
  printf '%s' "$port"
}

is_local_host() {
  local host="$1"
  [[ "$host" == "localhost" || "$host" == "127.0.0.1" || "$host" == "0.0.0.0" ]]
}

server_reachable() {
  local url="$1"
  curl -s --max-time 1 "$url/health" >/dev/null 2>&1
}

SERVER_PID=""

start_local_server() {
  local host="$1"
  local port="$2"
  local log_path="$3"
  local expr
  expr=$(printf 'Toska.run(["start","--host","%s","--port","%s","--env","dev"])' "$host" "$port")
  (cd "$ROOT_DIR" && MIX_ENV=dev mix run -e "$expr") >"$log_path" 2>&1 &
  SERVER_PID=$!
}

stop_local_server() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}

wait_for_server() {
  local url="$1"
  local attempts=60
  for ((i=0; i<attempts; i++)); do
    if server_reachable "$url"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

if ! command -v k6 >/dev/null 2>&1; then
  echo "k6 not found. Install it from https://k6.io/docs/get-started/installation/" >&2
  exit 1
fi

scenario="${1:-}"
if [[ "$scenario" != "kv" && "$scenario" != "replication" ]]; then
  echo "Usage: scripts/perf/run_k6.sh [kv|replication]" >&2
  exit 1
fi

report_dir="$(ensure_report_dir)"
export PERF_REPORT_DIR="$report_dir"

if [[ "${PERF_SKIP_ENV:-}" != "1" ]]; then
  write_env_metadata "$report_dir"
fi

BASE_URL="${BASE_URL:-http://localhost:4000}"
base_host="$(extract_host "$BASE_URL")"
base_port="$(extract_port "$BASE_URL" "$base_host")"
server_started=0
server_log="$report_dir/k6_${scenario}_server.log"

if ! server_reachable "$BASE_URL"; then
  if is_local_host "$base_host"; then
    echo "Starting Toska server for k6 at ${base_host}:${base_port}..."
    start_local_server "$base_host" "$base_port" "$server_log"
    server_started=1
    if ! wait_for_server "$BASE_URL"; then
      echo "Toska server did not become ready at ${BASE_URL}." >&2
      stop_local_server
      exit 1
    fi
  else
    echo "Toska server not reachable at ${BASE_URL}. Start it or set BASE_URL." >&2
    exit 1
  fi
fi

if [[ "$server_started" == "1" ]]; then
  trap stop_local_server EXIT
fi

if [[ -z "${K6_VUS:-}" ]]; then
  if [[ "$scenario" == "replication" ]]; then
    K6_VUS="10"
  else
    K6_VUS="20"
  fi
fi
K6_DURATION="${K6_DURATION:-30s}"

script_path="$ROOT_DIR/perf/k6/${scenario}.js"
summary_path="$report_dir/k6_${scenario}_summary.json"
config_path="$report_dir/k6_${scenario}_config.json"

cat <<CONFIG > "$config_path"
{
  "scenario": "${scenario}",
  "base_url": "${BASE_URL}",
  "vus": ${K6_VUS},
  "duration": "${K6_DURATION}"
}
CONFIG

BASE_URL="$BASE_URL" K6_VUS="$K6_VUS" K6_DURATION="$K6_DURATION" \
  k6 run --summary-export "$summary_path" "$script_path"

if [[ "${PERF_SKIP_REPORT:-}" != "1" ]]; then
  write_summary "$report_dir"
fi

printf 'k6 run complete. Results in %s\n' "$report_dir"
