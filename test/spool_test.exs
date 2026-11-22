defmodule Watchtower.SpoolTest do
  use ExUnit.Case

  defp state(dir, send), do: %{dir: dir, max_files: 2, send: send}

  @tag :tmp_dir
  test "stores batches on disk, drops the oldest, replays in order", %{tmp_dir: dir} do
    me = self()
    s = state(dir, fn body -> send(me, {:sent, body}) && :ok end)
    for b <- ["a", "b", "c"], do: :ok = Watchtower.Spool.store(s, b)
    assert length(Watchtower.Spool.files(s)) == 2
    assert Watchtower.Spool.replay(s) == :ok
    assert_received {:sent, "b"}
    assert_received {:sent, "c"}
    refute_received {:sent, "a"}
    assert Watchtower.Spool.files(s) == []
  end

  @tag :tmp_dir
  test "keeps files and order while offline", %{tmp_dir: dir} do
    s = state(dir, fn _ -> :error end)
    :ok = Watchtower.Spool.store(s, "x")
    assert Watchtower.Spool.replay(s) == :offline
    assert length(Watchtower.Spool.files(s)) == 1
  end

  test "spool_dir switches the traces exporter to the spool" do
    c = Watchtower.Config.new(service: "s", key: "wtk_fake", spool_dir: "/tmp/wt-spool")
    assert {Watchtower.Spool, %{dir: "/tmp/wt-spool", url: "http://localhost:4318/v1/traces", headers: [_]}} =
             Watchtower.Config.otel_env(c)[:traces_exporter]
    assert Watchtower.Config.otel_env(Watchtower.Config.new(service: "s"))[:traces_exporter] == :otlp
  end
end
