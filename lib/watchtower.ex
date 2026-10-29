defmodule Watchtower do
  @moduledoc """
  Watchtower over OpenTelemetry Erlang: key header, endpoint default, `wt.*`-safe attributes,
  a redaction hook and exception capture linked to the active trace.

  Configure the exporter in `config/runtime.exs`, before the `:opentelemetry` app starts:

      config :opentelemetry, Watchtower.Config.from_env("shop") |> Watchtower.Config.otel_env()
      config :opentelemetry_exporter, Watchtower.Config.from_env("shop") |> Watchtower.Config.exporter_env()
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias OpenTelemetry.Span

  @doc "Stores the config used by redaction (`Watchtower.Config`)."
  def put_config(%Watchtower.Config{} = c), do: :persistent_term.put({__MODULE__, :config}, c)

  def config, do: :persistent_term.get({__MODULE__, :config}, nil)

  @doc "Drops `wt.*` attributes, then applies the configured redactor (`fn {k, v} -> {k, v} | nil end`)."
  def redact(attrs) do
    redactor =
      case config() do
        %{redactor: r} when is_function(r, 1) -> r
        _ -> & &1
      end

    attrs
    |> Enum.reject(fn {k, _} -> String.starts_with?(to_string(k), "wt.") end)
    |> Enum.flat_map(fn kv ->
      case redactor.(kv) do
        nil -> []
        out -> [out]
      end
    end)
  end

  @doc "OTel exception attributes for a `kind, reason, stacktrace` triple, already redacted."
  def exception_attributes(kind, reason, stack, extra \\ []) do
    ex = Exception.normalize(kind, reason, stack)

    [
      {"exception.type", exception_type(ex)},
      {"exception.message", Exception.format_banner(kind, reason, stack)},
      {"exception.stacktrace", Exception.format_stacktrace(stack)}
    ]
    |> Kernel.++(extra)
    |> redact()
  end

  defp exception_type(%{__struct__: m}), do: inspect(m)
  defp exception_type(_), do: "erlang_error"

  @doc """
  Records an exception on the active span (so it carries the trace and span ids), or on a new
  `wt.exception` span when none is recording. Returns `:ok`.
  """
  def capture_exception(kind, reason, stack, extra \\ []) do
    attrs = exception_attributes(kind, reason, stack, extra)
    msg = Exception.format_banner(kind, reason, stack)
    ctx = Tracer.current_span_ctx()

    if Span.is_recording(ctx) do
      record(ctx, attrs, msg)
    else
      Tracer.with_span "wt.exception" do
        record(Tracer.current_span_ctx(), attrs, msg)
      end
    end

    :ok
  end

  defp record(ctx, attrs, msg) do
    Span.add_event(ctx, "exception", attrs)
    Span.set_status(ctx, OpenTelemetry.status(:error, msg))
    :ok
  end
end
