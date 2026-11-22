defmodule Watchtower.EmbeddedTest do
  use ExUnit.Case

  alias Watchtower.Embedded

  test "ETS readings count objects and bytes" do
    t = :ets.new(:wt_embedded_test, [:set, :public])
    :ets.insert(t, {:a, 1})
    r = Embedded.ets_readings(t)
    assert r["wt.embedded.keys"] == 1
    assert r["wt.embedded.memory.used"] > 0
  end

  test "DETS readings include the file size" do
    path = Path.join(System.tmp_dir!(), "wt_embedded_#{System.unique_integer([:positive])}.dets")
    {:ok, t} = :dets.open_file(:wt_dets_test, file: String.to_charlist(path))
    :ok = :dets.insert(t, {:k, "v"})
    r = Embedded.dets_readings(t)
    assert r["wt.embedded.keys"] == 1 and r["wt.embedded.file.size"] > 0
    :dets.close(t)
    File.rm(path)
  end

  test "collect keeps known non-negative numbers and survives a store that went away" do
    attrs = %{"db.system.name" => "ets", "db.namespace" => "x"}
    out = Embedded.collect({attrs, fn -> %{"wt.embedded.keys" => 3, "wt.embedded.readers" => -1, "nope" => 1} end})
    assert out == [{:"wt.embedded.keys", [{3, attrs}]}]
    assert Embedded.collect({attrs, fn -> :ets.info(:no_such_table, :size) + 1 end}) == []
  end

  test "mnesia transaction returns the result and system readings are numbers" do
    :mnesia.start()
    assert {:atomic, :ok} = Embedded.mnesia_transaction(fn -> :ok end, "orders")
    assert {:aborted, :nope} = Embedded.mnesia_transaction(fn -> :mnesia.abort(:nope) end)
    r = Embedded.mnesia_system_readings()
    assert is_integer(r["wt.embedded.transactions"]) and r["wt.embedded.transactions"] >= 1
    :mnesia.stop()
  end
end
