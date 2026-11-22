defmodule Watchtower.SignalsTest do
  use ExUnit.Case

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  # A fake OTLP/HTTP endpoint: each request is sent to `me` as {:otlp, path, auth, body}.
  defp fake_otlp(me) do
    {:ok, ls} = :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(ls)
    spawn_link(fn -> accept(ls, me) end)
    "http://127.0.0.1:#{port}"
  end

  defp accept(ls, me) do
    {:ok, s} = :gen_tcp.accept(ls)
    {path, len, auth} = head(s, nil, 0, nil)
    :ok = :inet.setopts(s, packet: :raw)
    {:ok, body} = if len > 0, do: :gen_tcp.recv(s, len, 5_000), else: {:ok, ""}
    send(me, {:otlp, path, auth, body})
    :gen_tcp.send(s, "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
    :gen_tcp.close(s)
    accept(ls, me)
  end

  defp head(s, path, len, auth) do
    case :gen_tcp.recv(s, 0, 5_000) do
      {:ok, {:http_request, _, {:abs_path, p}, _}} -> head(s, p, len, auth)
      {:ok, {:http_header, _, :"Content-Length", _, v}} -> head(s, path, String.to_integer(v), auth)
      {:ok, {:http_header, _, :Authorization, _, v}} -> head(s, path, len, v)
      {:ok, {:http_header, _, _, _, _}} -> head(s, path, len, auth)
      {:ok, :http_eoh} -> {path, len, auth}
    end
  end

  defp logs_until(text, acc \\ "") do
    receive do
      {:otlp, "/v1/logs", "Bearer wtk_fake", body} ->
        acc = acc <> body
        if String.contains?(acc, text), do: acc, else: logs_until(text, acc)

      {:otlp, _, _, _} ->
        logs_until(text, acc)
    after
      5_000 -> flunk("no /v1/logs request carrying #{inspect(text)}")
    end
  end

  test "Logger records reach /v1/logs with the active trace and span ids" do
    url = fake_otlp(self())
    c = Watchtower.Config.new(service: "s", key: "wtk_fake", endpoint: url)
    :ok = Watchtower.Logs.install(c)

    try do
      ctx =
        Tracer.with_span "op" do
          Logger.warning("hello from logger")
          Tracer.current_span_ctx()
        end

      body = logs_until("hello from logger")
      assert String.contains?(body, <<OpenTelemetry.Span.trace_id(ctx)::128>>), "log record carries the trace id"
      assert String.contains?(body, <<OpenTelemetry.Span.span_id(ctx)::64>>), "log record carries the span id"
    after
      Watchtower.Logs.uninstall()
    end
  end

  test "metrics reader exports OTLP with delta temporality for counters and histograms" do
    c = Watchtower.Config.new(service: "s", key: "wtk_fake")
    [readers: [%{module: :otel_metric_reader, config: r}]] = Watchtower.Config.metrics_env(c)
    assert {:otel_exporter_metrics_otlp, %{endpoints: ["http://localhost:4318/v1/metrics"], headers: [_]}} = r.exporter
    assert r.default_temporality_mapping.counter == :temporality_delta
    assert r.default_temporality_mapping.histogram == :temporality_delta
    assert r.default_temporality_mapping.updown_counter == :temporality_cumulative
    assert Watchtower.Config.metrics_env(%{c | metrics: false}) == [readers: []]
    assert :ok = Watchtower.Logs.install(%{c | logs: false})
  end

  test "spool_dir wraps the logs and metrics exporters in per-signal spools" do
    c = Watchtower.Config.new(service: "s", key: "wtk_fake", spool_dir: "/tmp/wt-spool")

    assert {Watchtower.Spool, %{dir: "/tmp/wt-spool/metrics", url: "http://localhost:4318/v1/metrics", inner: :otel_exporter_metrics_otlp}} =
             Watchtower.Config.signal_exporter(c, :metrics)

    assert {Watchtower.Spool, %{dir: "/tmp/wt-spool/logs", inner: :otel_exporter_logs_otlp}} = Watchtower.Config.signal_exporter(c, :logs)
  end

  defmodule Inner do
    def export(_kind, _data, _resource, me), do: send(me, :inner_export) && :ok
    def shutdown(_), do: :ok
  end

  @tag :tmp_dir
  test "a metrics spool replays stored batches before the next export", %{tmp_dir: dir} do
    me = self()
    s = %{dir: dir, max_files: 5, mod: Inner, inner: me, send: fn body -> send(me, {:sent, body}) && :ok end}
    :ok = Watchtower.Spool.store(s, "old-batch")
    assert :ok = Watchtower.Spool.export(:metrics, [], :resource, s)
    assert_received {:sent, "old-batch"}
    assert_received :inner_export
    assert Watchtower.Spool.files(s) == []
  end

  test "switches" do
    System.put_env("WATCHTOWER_METRICS", "off")
    System.put_env("OTEL_LOGS_EXPORTER", "none")

    try do
      c = Watchtower.Config.from_env("s")
      refute c.metrics
      refute c.logs
    after
      System.delete_env("WATCHTOWER_METRICS")
      System.delete_env("OTEL_LOGS_EXPORTER")
    end

    assert Watchtower.Config.from_env("s").logs
  end
end
