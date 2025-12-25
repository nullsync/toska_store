# Performance Testing

This directory contains performance tests and reporting helpers for Toska.
The goal is reproducible, publishable results with clear configuration.

## Structure

- bench/ - in-process microbenchmarks (Benchee)
- k6/ - HTTP load tests (k6)
- reports/ - generated results (ignored by git)

## Quick start

1) Start the server in another terminal:

   mix run -e "Toska.run([\"start\", \"--port\", \"4000\"])"

2) Run all performance tests and generate a report:

   scripts/perf/run_all.sh

The report will be written to perf/reports/<timestamp>/summary.md.

## Microbenchmarks

Run the KV store microbench:

  scripts/perf/run_microbench.sh

Optional environment variables:

- PERF_DATASET_SIZE (default: 100000)
- PERF_VALUE_SIZE (default: 128)
- PERF_MGET_SIZE (default: 10)
- PERF_LIST_LIMIT (default: 100)
- PERF_PARALLEL (default: 1)
- PERF_TIME (seconds, default: 5)
- PERF_WARMUP (seconds, default: 2)
- PERF_INCLUDE_SNAPSHOT (true/false)

Run the replication microbench:

  scripts/perf/run_replication_bench.sh

Options:

- PERF_REPLICA_SNAPSHOT_KEYS (default: 1000)
- PERF_REPLICA_AOF_ENTRIES (default: 100)
- PERF_REPLICA_POLL_MS (default: 50)
- PERF_REPLICA_TIMEOUT_MS (default: 2000)

## HTTP Load (k6)

Install k6 first (https://k6.io/docs/get-started/installation/).

KV endpoint load:

  scripts/perf/run_k6.sh kv

Replication endpoint load:

  scripts/perf/run_k6.sh replication

Options:

- BASE_URL (default: http://localhost:4000)
- K6_VUS (default: 20)
- K6_DURATION (default: 30s)

## Baseline comparisons

Baseline runs (K6_DURATION=60s, default KEY_SPACE=10000, VALUE_SIZE=128, local server) with stable
request tags to avoid high-cardinality URLs.

KV endpoints:

| VUs | RPS | p50 (ms) | p90 (ms) | p99 (ms) | Error rate |
|---|---|---|---|---|---|
| 10 | 480.55 | 0.45 | 1.14 | 1.79 | 0.00% |
| 20 | 952.29 | 0.59 | 1.56 | 4.45 | 0.00% |
| 30 | 1433.89 | 0.52 | 1.42 | 4.07 | 0.00% |
| 40 | 1914.10 | 0.55 | 1.49 | 2.80 | 0.00% |

Replication endpoints:

| VUs | RPS | p50 (ms) | p90 (ms) | p99 (ms) | Error rate |
|---|---|---|---|---|---|
| 10 | 252.21 | 0.85 | 16.81 | 24.31 | 0.00% |
| 20 | 447.86 | 1.03 | 33.06 | 41.79 | 0.00% |
| 30 | 604.03 | 1.62 | 47.13 | 59.20 | 0.00% |
| 40 | 753.38 | 1.85 | 55.34 | 68.23 | 0.00% |

Report dirs used for the table:

- perf/reports/baseline-kv-vu10-2025-12-25T03-04-27Z
- perf/reports/baseline-kv-vu20-2025-12-25T03-04-27Z
- perf/reports/2025-12-25T02-59-36Z (kv, 30 VUs)
- perf/reports/baseline-kv-vu40-2025-12-25T03-04-27Z
- perf/reports/baseline-replication-vu10-2025-12-25T03-04-27Z
- perf/reports/baseline-replication-vu20-2025-12-25T03-04-27Z
- perf/reports/2025-12-25T02-59-36Z (replication, 30 VUs)
- perf/reports/baseline-replication-vu40-2025-12-25T03-04-27Z

## Redis comparison (RESP vs HTTP)

Run config: 100000 requests, concurrency 50, value size 128 bytes, key space 10000.

| Operation | Redis (ops/sec) | Toska (ops/sec) |
|---|---|---|
| SET/PUT | 259067.36 | 20375.35 |
| GET | 242130.77 | 28522.00 |

Toska latency (ms):

| Operation | avg | p50 | p90 | p99 | errors |
|---|---|---|---|---|---|
| PUT | 2.44 | 2.33 | 2.96 | 4.41 | 0 |
| GET | 1.75 | 1.66 | 2.09 | 2.84 | 0 |

Report dir: perf/reports/2025-12-25T04-28-04Z

## Publishing results

Each run writes:

- env.json (system + runtime metadata)
- microbench_*.json (in-process stats)
- k6_*_summary.json (HTTP load stats)
- summary.md (human-readable report)

Share the summary.md and raw JSON for reproducibility.
