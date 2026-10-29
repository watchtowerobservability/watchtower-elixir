defmodule Watchtower.Config do
  @moduledoc "Watchtower settings and the OTel Erlang environment they translate to."

  @default_endpoint "http://localhost:4318"
  defstruct [:service, :key, :environment, :release, :redactor, endpoint: @default_endpoint]

  @doc "Reads `WT_OTLP_ENDPOINT`, `WT_INGEST_KEY`, `WT_ENVIRONMENT`, `WT_RELEASE`."
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
      release: get.("WT_RELEASE")
    )
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
      traces_exporter: :otlp,
      span_processor: :batch
    ]
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
