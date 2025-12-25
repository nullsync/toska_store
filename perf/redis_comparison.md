# Toska vs Redis comparison (RESP vs HTTP)

## Run configuration

- Requests: 100000
- Concurrency: 50
- Value size: 128 bytes
- Key space: 10000
- Redis: redis-benchmark (RESP)
- Toska: HTTP benchmark (`scripts/perf/toska_http_bench.exs`)
- Report artifacts: `perf/reports/2025-12-25T04-28-04Z`

## Throughput (ops/sec)

| Operation | Redis | Toska |
|---|---|---|
| SET/PUT | 259067.36 | 20375.35 |
| GET | 242130.77 | 28522.00 |

## Toska latency (ms)

| Operation | avg | p50 | p90 | p99 | errors |
|---|---|---|---|---|---|
| PUT | 2.44 | 2.33 | 2.96 | 4.41 | 0 |
| GET | 1.75 | 1.66 | 2.09 | 2.84 | 0 |

## Interpretation

- Redis is ~9-12x higher throughput in this run, which is expected given RESP vs HTTP and JSON overhead.
- Toska numbers include HTTP parsing, JSON decode/encode, and Plug stack latency; Redis numbers do not.
- Both benchmarks used similar request counts and concurrency, but the protocols are not equivalent, so this is directional, not a strict apples-to-apples result.

## Plan to improve Toska throughput

1) Protocol parity and transport overhead
   - Add a lightweight RESP-compatible endpoint or binary protocol for KV ops.
   - Re-run the comparison using the same client/protocol to establish a fair baseline.

2) HTTP path optimizations
   - Offer a fast-path for PUT/GET with minimal JSON work (e.g., raw body, no JSON decode when not needed).
   - Evaluate Plug pipeline (disable logging and extra plugs in benchmark mode).

3) KV store hot path
   - Profile the KVStore get/put functions under load to identify hotspots.
   - Optimize data structure lookups and reduce per-request allocations.

4) Concurrency and batching
   - Add bulk endpoints or pipelining (e.g., mget/mset) to reduce per-request overhead.
   - Evaluate per-connection state and reduce cross-process contention.

5) Measurement rigor
   - Add a repeatable, versioned baseline harness with pinned configs.
   - Track improvements with a consistent report format and retain raw JSON.
