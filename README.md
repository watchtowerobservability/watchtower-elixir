# watchtower (Elixir)

Thin Watchtower distribution over OpenTelemetry Erlang/Elixir: `Authorization: Bearer` key header,
endpoint default, `wt.*`-safe attributes, redaction hook, and exception capture linked to the active trace.

## Install

```elixir
{:watchtower, github: "watchtowerobservability/watchtower-elixir", tag: "v0.1.1"}
```

## Quick start

```elixir
# config/runtime.exs
c = Watchtower.Config.from_env("shop")
config :opentelemetry, Watchtower.Config.otel_env(c)
config :opentelemetry_exporter, Watchtower.Config.exporter_env(c)

config :opentelemetry_experimental, Watchtower.Config.metrics_env(c)   # OTLP metrics reader

# Application.start/2
Watchtower.put_config(Watchtower.Config.from_env("shop"))
Watchtower.LoggerHandler.install()
Watchtower.Logs.install(Watchtower.Config.from_env("shop"))           # Logger -> OTLP logs
```

Logs and metrics use the OTel Erlang logs and metrics SDKs (`opentelemetry_experimental`, still
experimental upstream). Logger records carry the trace and span ids of the calling process. Meters
come from `opentelemetry_api_experimental` (`:otel_meter`); counters and histograms use delta
temporality unless `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`, exported every
`OTEL_METRIC_EXPORT_INTERVAL` ms. There is no official BEAM runtime metrics package yet.

## Integrations

| Integration | Use |
| --- | --- |
| Logger handler | `Watchtower.LoggerHandler.install()` captures crash reports on the active span |
| Plug / Phoenix | `use Watchtower.Plug` in the endpoint or router (tracing: `opentelemetry_phoenix`) |
| Oban | `Watchtower.Oban.attach()` (tracing: `opentelemetry_oban`) |
| ETS, DETS, Mnesia, Cachex | `Watchtower.Embedded.observe_ets/1`, `observe_dets/1`, `observe_mnesia/1`, `observe_mnesia_system/0`, `observe_cachex/1`: `wt.embedded.*` metrics; `mnesia_transaction/2`: client spans |
| Manual | `Watchtower.capture_exception(kind, reason, stacktrace)` |

## Configuration

| Variable | Meaning |
| --- | --- |
| `WT_INGEST_KEY` | secret ingest key, masked in `inspect`; never commit it |
| `WT_OTLP_ENDPOINT` | OTLP/HTTP base, default `http://localhost:4318` |
| `WT_SERVICE` | service name (default for `Config.from_env/1`) |
| `WT_ENVIRONMENT`, `WT_RELEASE` | `deployment.environment.name`, `service.version` |
| `WATCHTOWER_LOGS`, `WATCHTOWER_METRICS` | `on`/`off`, default `on`; `OTEL_LOGS_EXPORTER` / `OTEL_METRICS_EXPORTER=none` also turn one off |
| `WT_SPOOL_DIR` | disk spool for traces (root), logs (`logs/`) and metrics (`metrics/`), 500 batches each |

Redaction: `Config.new(redactor: fn {k, v} -> {k, v} | nil end)`, applied to exception attributes.

## Provenance

Every release artifact carries a GitHub build attestation. Verify one with
`gh attestation verify <file> --repo watchtowerobservability/watchtower-elixir`.

## License

Apache-2.0. Source of truth is the Watchtower monorepo; this repository is a published mirror.
