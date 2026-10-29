# watchtower (Elixir)

Thin Watchtower distribution over OpenTelemetry Erlang/Elixir: `Authorization: Bearer` key header,
endpoint default, `wt.*`-safe attributes, redaction hook, and exception capture linked to the active trace.

## Install

```elixir
{:watchtower, github: "watchtowerobservability/watchtower-elixir", tag: "v0.1.0"}
```

## Quick start

```elixir
# config/runtime.exs
c = Watchtower.Config.from_env("shop")
config :opentelemetry, Watchtower.Config.otel_env(c)
config :opentelemetry_exporter, Watchtower.Config.exporter_env(c)

# Application.start/2
Watchtower.put_config(Watchtower.Config.from_env("shop"))
Watchtower.LoggerHandler.install()
```

## Integrations

| Integration | Use |
| --- | --- |
| Logger handler | `Watchtower.LoggerHandler.install()` captures crash reports on the active span |
| Plug / Phoenix | `use Watchtower.Plug` in the endpoint or router (tracing: `opentelemetry_phoenix`) |
| Oban | `Watchtower.Oban.attach()` (tracing: `opentelemetry_oban`) |
| Manual | `Watchtower.capture_exception(kind, reason, stacktrace)` |

## Configuration

| Variable | Meaning |
| --- | --- |
| `WT_INGEST_KEY` | secret ingest key, masked in `inspect`; never commit it |
| `WT_OTLP_ENDPOINT` | OTLP/HTTP base, default `http://localhost:4318` |
| `WT_SERVICE` | service name (default for `Config.from_env/1`) |
| `WT_ENVIRONMENT`, `WT_RELEASE` | `deployment.environment.name`, `service.version` |

Redaction: `Config.new(redactor: fn {k, v} -> {k, v} | nil end)`, applied to exception attributes.

## Provenance

Every release artifact carries a GitHub build attestation. Verify one with
`gh attestation verify <file> --repo watchtowerobservability/watchtower-elixir`.

## License

Apache-2.0. Source of truth is the Watchtower monorepo; this repository is a published mirror.
