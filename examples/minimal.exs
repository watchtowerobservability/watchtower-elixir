Mix.install([{:watchtower, path: ".."}])

# Run with WT_INGEST_KEY and WT_OTLP_ENDPOINT set.
config = Watchtower.Config.from_env("example")
Application.put_all_env(opentelemetry: Watchtower.Config.otel_env(config), opentelemetry_exporter: Watchtower.Config.exporter_env(config))
Watchtower.put_config(config)
{:ok, _} = Application.ensure_all_started(:opentelemetry)
Watchtower.LoggerHandler.install()

require OpenTelemetry.Tracer, as: Tracer

Tracer.with_span "checkout" do
  try do
    raise "payment failed"
  rescue
    e -> Watchtower.capture_exception(:error, e, __STACKTRACE__)
  end
end

Process.sleep(2_000)
