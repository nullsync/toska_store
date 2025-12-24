# ToskaStore

ToskaStore is a disk-backed string KV store with a clean HTTP/JSON surface and a minimal CLI. It is built in Elixir, designed for clarity, and intended to scale without surprises.

## Quick Start

```bash
mix deps.get
mix compile
cd apps/toska
mix escript.build
./toska start
```

Smoke test:

```bash
curl -s -X PUT http://localhost:4000/kv/hello \
  -H 'content-type: application/json' \
  -d '{"value":"world"}'

curl -s http://localhost:4000/kv/hello
```

## Docs

- [docs/guide.md](docs/guide.md) - full install/build/config/API/CLI/development guide
- [docs/kv-store-changes.md](docs/kv-store-changes.md) - KV store change log and milestones

## License

MIT

Tip: `./toska status` and `/health` are the fastest sanity checks.
