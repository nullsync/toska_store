FROM elixir:1.18.1-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY mix.exs mix.lock ./
COPY config ./config
COPY apps ./apps

RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get
RUN mix compile

WORKDIR /app/apps/toska
RUN mix escript.build

FROM elixir:1.18.1-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/apps/toska/toska /app/toska

ENV TOSKA_CONFIG_DIR=/data
ENV TOSKA_DATA_DIR=/data

EXPOSE 4000

ENTRYPOINT ["/app/toska", "start", "--host", "0.0.0.0", "--port", "4000"]
