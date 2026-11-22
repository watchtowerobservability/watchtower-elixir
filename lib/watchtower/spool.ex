defmodule Watchtower.Spool do
  @moduledoc """
  Offline buffer: an `:otel_exporter` that wraps the OTLP exporter of one signal
  (`:opentelemetry_exporter` for traces by default, `inner: :otel_exporter_logs_otlp` or
  `:otel_exporter_metrics_otlp`). A batch the exporter fails to send is written to `dir` as an
  OTLP protobuf request (the exporter's own encoding) and POSTed again,
  oldest first, before the next export, so it survives a restart. At most `max_files` batches
  are kept (drop-oldest). Delivery stays at-least-once.

  Enabled by `spool_dir` in `Watchtower.Config` (`WT_SPOOL_DIR`); `otel_env/1` then sets
  `traces_exporter: {Watchtower.Spool, %{...}}`, and `Config.signal_exporter/2` wraps logs and metrics.
  """
  @behaviour :otel_exporter

  @impl true
  def init(%{dir: dir, url: url} = c) do
    File.mkdir_p!(dir)
    mod = Map.get(c, :inner, :opentelemetry_exporter)
    {:ok, inner} = mod.init(Map.get(c, :exporter, %{}))
    headers = Map.get(c, :headers, [])

    {:ok,
     %{
       dir: dir,
       mod: mod,
       inner: inner,
       max_files: max(Map.get(c, :max_files, 500), 1),
       send: Map.get(c, :send, fn body -> post(url, headers, body) end)
     }}
  end

  @impl true
  def export(kind, data, resource, s) do
    replay(s)

    case s.mod.export(kind, data, resource, s.inner) do
      :ok ->
        :ok

      other ->
        with {:ok, body} <- encode(kind, data, resource), do: store(s, body)
        other
    end
  end

  @impl true
  def shutdown(s), do: s.mod.shutdown(s.inner)

  @doc "Spooled batch files, oldest first (names start with the write time and a counter)."
  def files(%{dir: dir}), do: dir |> Path.join("*.otlp") |> Path.wildcard() |> Enum.sort()

  @doc "Writes one encoded batch, dropping the oldest files beyond `max_files`."
  def store(%{dir: dir, max_files: keep} = s, body) do
    have = files(s)
    have |> Enum.take(max(length(have) - keep + 1, 0)) |> Enum.each(&File.rm/1)
    t = System.system_time(:millisecond) |> Integer.to_string() |> String.pad_leading(13, "0")
    n = System.unique_integer([:positive, :monotonic]) |> Integer.to_string() |> String.pad_leading(12, "0")
    name = Path.join(dir, "#{t}-#{n}.otlp")

    # disk full or not writable: the batch is lost, as without a spool
    with :ok <- File.write(name <> ".tmp", body), do: File.rename(name <> ".tmp", name)
  end

  @doc "Sends spooled batches in order; stops at the first failure so order is kept."
  def replay(%{send: send} = s) do
    Enum.reduce_while(files(s), :ok, fn f, :ok ->
      with {:ok, body} <- File.read(f), :ok <- send.(body) do
        File.rm(f)
        {:cont, :ok}
      else
        _ -> {:halt, :offline}
      end
    end)
  end

  # Same encoding the OTLP exporters use for http_protobuf; on any change there the batch is not
  # spooled rather than crashing the exporter.
  defp encode(:traces, tab, resource) do
    case :otel_otlp_traces.to_proto(tab, resource) do
      :empty -> :empty
      proto -> {:ok, :opentelemetry_exporter_trace_service_pb.encode_msg(proto, :export_trace_service_request)}
    end
  rescue
    _ -> :error
  end

  defp encode(:metrics, metrics, resource) do
    case :otel_otlp_metrics.to_proto(metrics, resource) do
      :empty -> :empty
      proto -> {:ok, :opentelemetry_exporter_metrics_service_pb.encode_msg(proto, :export_metrics_service_request)}
    end
  rescue
    _ -> :error
  end

  defp encode(:logs, {logs, config}, resource) do
    case :otel_otlp_logs.to_proto(logs, resource, config) do
      :empty -> :empty
      proto -> {:ok, :opentelemetry_exporter_logs_service_pb.encode_msg(proto, :export_logs_service_request)}
    end
  rescue
    _ -> :error
  end

  defp encode(_kind, _data, _resource), do: :error

  defp post(url, headers, body) do
    hs = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
    req = {String.to_charlist(url), hs, ~c"application/x-protobuf", body}

    case :httpc.request(:post, req, [timeout: 10_000, connect_timeout: 5_000], []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 -> :ok
      _ -> :error
    end
  end
end
