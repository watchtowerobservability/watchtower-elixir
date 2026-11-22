defmodule Watchtower.Config do
  @moduledoc "Watchtower settings and the OTel Erlang environment they translate to."

  @default_endpoint "http://localhost:4318"
  defstruct [:service, :key, :environment, :release, :redactor, :spool_dir,
             endpoint: @default_endpoint, logs: true, metrics: true]

  @doc """
  Reads `WT_OTLP_ENDPOINT`, `WT_INGEST_KEY`, `WT_ENVIRONMENT`, `WT_RELEASE`, `WT_SPOOL_DIR`, and the
  `WATCHTOWER_LOGS` / `WATCHTOWER_METRICS` switches (on unless `off`; `OTEL_LOGS_EXPORTER` /
  `OTEL_METRICS_EXPORTER=none` also turn a signal off).
  """
  def from_env(service \\ System.get_env("WT_SERVICE")) do
    get = fn k ->
      case System.get_env(k) do
        v when v in [nil, ""] -> nil
        v -> v
      end
    end

    new(
      service: service,
      key: get.("WT_INGEST_KEY"),
      endpoint: get.("WT_OTLP_ENDPOINT"),
      environment: get.("WT_ENVIRONMENT"),
      release: get.("WT_RELEASE"),
      spool_dir: get.("WT_SPOOL_DIR"),
      logs: switch_on?("WATCHTOWER_LOGS", "OTEL_LOGS_EXPORTER"),
      metrics: switch_on?("WATCHTOWER_METRICS", "OTEL_METRICS_EXPORTER")
    )
  end

  @doc false
  def switch_on?(env, otel_exporter) do
    norm = fn k -> (System.get_env(k) || "") |> String.trim() |> String.downcase() end
    norm.(otel_exporter) != "none" and norm.(env) not in ["off", "false", "0", "no"]
  end

  def new(opts) do
    c = struct!(__MODULE__, Enum.reject(opts, fn {_, v} -> is_nil(v) end))
    %{c | endpoint: String.trim_trailing(c.endpoint, "/")}
  end

  @doc "`authorization: Bearer <key>` header list for the exporter."
  def headers(%__MODULE__{key: nil}), do: []
  def headers(%__MODULE__{key: k}), do: [{"authorization", "Bearer " <> k}]

  @doc "Keyword for `config :opentelemetry`."
  def otel_env(%__MODULE__{} = c) do
    attrs =
      [
        {"deployment.environment.name", c.environment},
        {"service.version", c.release}
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    [
      resource: Map.put(attrs, "service.name", c.service),
      traces_exporter: traces_exporter(c),
      span_processor: :batch
    ]
  end

  # With a spool dir, failed batches go to disk and are resent (Watchtower.Spool).
  defp traces_exporter(%__MODULE__{spool_dir: nil}), do: :otlp

  defp traces_exporter(%__MODULE__{spool_dir: dir} = c),
    do: {Watchtower.Spool, %{dir: dir, url: c.endpoint <> "/v1/traces", headers: headers(c)}}

  @doc """
  `{module, config}` OTLP exporter for `:logs` or `:metrics`, spooled under `<spool_dir>/<signal>`
  when a spool dir is set.
  """
  def signal_exporter(%__MODULE__{} = c, signal) when signal in [:logs, :metrics] do
    url = "#{c.endpoint}/v1/#{signal}"
    mod = if signal == :logs, do: :otel_exporter_logs_otlp, else: :otel_exporter_metrics_otlp
    opts = %{endpoints: [url], headers: headers(c), protocol: :http_protobuf}

    case c.spool_dir do
      nil ->
        {mod, opts}

      dir ->
        {Watchtower.Spool,
         %{dir: Path.join(dir, to_string(signal)), url: url, headers: headers(c), inner: mod, exporter: opts}}
    end
  end

  @doc """
  Keyword for `config :opentelemetry_experimental` (the OTel Erlang metrics SDK): one periodic
  OTLP reader, every `OTEL_METRIC_EXPORT_INTERVAL` ms (default 60000). Counters and histograms
  use delta temporality unless `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`.
  Empty when metrics are off.
  """
  def metrics_env(%__MODULE__{metrics: false}), do: [readers: []]

  def metrics_env(%__MODULE__{} = c) do
    reader = %{exporter: signal_exporter(c, :metrics), export_interval_ms: export_interval()}

    reader =
      case System.get_env("OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE", "") |> String.downcase() do
        "cumulative" -> reader
        _ -> Map.put(reader, :default_temporality_mapping, delta_mapping())
      end

    [readers: [%{module: :otel_metric_reader, config: reader}]]
  end

  @doc false
  def delta_mapping do
    %{
      counter: :temporality_delta,
      observable_counter: :temporality_delta,
      histogram: :temporality_delta,
      updown_counter: :temporality_cumulative,
      observable_updowncounter: :temporality_cumulative,
      observable_gauge: :temporality_cumulative
    }
  end

  defp export_interval do
    case Integer.parse(System.get_env("OTEL_METRIC_EXPORT_INTERVAL", "")) do
      {ms, ""} when ms > 0 -> ms
      _ -> 60_000
    end
  end

  @doc "Keyword for `config :opentelemetry_exporter`."
  def exporter_env(%__MODULE__{} = c) do
    [
      otlp_protocol: :http_protobuf,
      otlp_endpoint: c.endpoint,
      otlp_headers: headers(c)
    ]
  end

  defimpl Inspect do
    # The key must never reach logs or IEx output.
    def inspect(c, opts) do
      Inspect.Any.inspect(%{c | key: c.key && "***", redactor: c.redactor && :fun}, opts)
    end
  end
end
