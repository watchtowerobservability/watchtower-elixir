defmodule Watchtower.Embedded do
  @moduledoc """
  In-VM and embedded stores: ETS, DETS, Mnesia and Cachex. `wt.embedded.*` health metrics through
  the OTel Erlang metrics SDK (`:otel_meter`), plus spans for Mnesia transactions. Keys and values
  are never recorded.

      Watchtower.Embedded.observe_ets(:sessions)
      Watchtower.Embedded.observe_dets(:jobs_dets)
      Watchtower.Embedded.observe_mnesia(:orders)       # per table
      Watchtower.Embedded.observe_mnesia_system()       # commits, aborts, restarts, held locks
      Watchtower.Embedded.observe_cachex(:my_cache)     # start Cachex with stats enabled
      Watchtower.Embedded.mnesia_transaction(fn -> :mnesia.write(rec) end, "orders")

  Any other store: `observe(system, namespace, fn -> %{"wt.embedded.keys" => n} end)`.
  """
  require OpenTelemetry.Tracer, as: Tracer

  @gauges ~w(file.size wal.size map.size map.used memory.used cache.size keys compaction.pending
             transactions.open free_pages levels.files snapshots.open iterators.open readers)
  @counters ~w(cache.hits cache.misses cache.evictions cache.rejections lock.waits lock.wait_time
               compactions compaction.duration flushes transactions bytes.written bytes.read)

  @doc "Metric names the backend understands (gauges first, then cumulative counters)."
  def names, do: Enum.map(@gauges ++ @counters, &("wt.embedded." <> &1))

  @doc """
  Read `fun.()` (a map of metric name => non-negative number) at each collection, tagged
  `db.system.name` and `db.namespace`. Unknown names and negative values are ignored; a store that
  went away (the read raises) reports nothing.
  """
  def observe(system, namespace, fun) when is_function(fun, 0) do
    meter = :opentelemetry_experimental.get_meter()
    gauges = for n <- @gauges, do: :otel_meter.create_observable_gauge(meter, atom("wt.embedded." <> n), %{})
    counters = for n <- @counters, do: :otel_meter.create_observable_counter(meter, atom("wt.embedded." <> n), %{})
    attrs = %{"db.system.name" => to_string(system), "db.namespace" => to_string(namespace)}
    :otel_meter.register_callback(meter, gauges ++ counters, &__MODULE__.collect/1, {attrs, fun})
  end

  # names() is a fixed list, so these atoms are bounded
  defp atom(name), do: String.to_atom(name)

  @doc false
  def collect({attrs, fun}) do
    readings =
      try do
        fun.()
      rescue
        _ -> %{}
      catch
        _, _ -> %{}
      end

    readings = if is_map(readings), do: readings, else: %{}

    for name <- names(), v = Map.get(readings, name), is_number(v) and v >= 0 do
      {atom(name), [{v, attrs}]}
    end
  end

  @word :erlang.system_info(:wordsize)

  @doc "ETS readings: object count and memory in bytes."
  def ets_readings(table) do
    %{"wt.embedded.keys" => :ets.info(table, :size), "wt.embedded.memory.used" => :ets.info(table, :memory) * @word}
  end

  def observe_ets(table), do: observe("ets", table, fn -> ets_readings(table) end)

  @doc "DETS readings: object count and file size."
  def dets_readings(table) do
    %{"wt.embedded.keys" => :dets.info(table, :size), "wt.embedded.file.size" => :dets.info(table, :file_size)}
  end

  def observe_dets(table), do: observe("dets", table, fn -> dets_readings(table) end)

  @doc "Mnesia table readings: record count and memory (words, except disc_only_copies in bytes)."
  def mnesia_readings(table) do
    mem = :mnesia.table_info(table, :memory)
    bytes = if :mnesia.table_info(table, :storage_type) == :disc_only_copies, do: mem, else: mem * @word
    %{"wt.embedded.keys" => :mnesia.table_info(table, :size), "wt.embedded.memory.used" => bytes}
  end

  def observe_mnesia(table), do: observe("mnesia", table, fn -> mnesia_readings(table) end)

  @doc "Node-wide Mnesia readings: committed transactions, lock waits (queue) and open transactions."
  def mnesia_system_readings do
    %{
      "wt.embedded.transactions" => :mnesia.system_info(:transaction_commits),
      "wt.embedded.lock.waits" => length(:mnesia.system_info(:lock_queue)),
      "wt.embedded.transactions.open" => length(:mnesia.system_info(:transactions))
    }
  end

  def observe_mnesia_system, do: observe("mnesia", node(), &mnesia_system_readings/0)

  @doc "Cachex readings: size, and hits/misses/evictions when the cache was started with stats."
  def cachex_readings(cache) do
    size = case apply(Cachex, :size, [cache]) do
      {:ok, n} -> n
      _ -> nil
    end

    stats = case apply(Cachex, :stats, [cache]) do
      {:ok, s} when is_map(s) -> s
      _ -> %{}
    end

    %{
      "wt.embedded.keys" => size,
      "wt.embedded.cache.hits" => Map.get(stats, :hits),
      "wt.embedded.cache.misses" => Map.get(stats, :misses),
      "wt.embedded.cache.evictions" => Map.get(stats, :evictions)
    }
  end

  def observe_cachex(cache), do: observe("cachex", cache, fn -> cachex_readings(cache) end)

  @doc """
  `:mnesia.transaction(fun)` inside a client span; `{:aborted, reason}` marks the span failed.
  Returns what `:mnesia.transaction/1` returns.
  """
  def mnesia_transaction(fun, table \\ nil) do
    attrs = %{"db.system.name" => "mnesia", "db.operation.name" => "transaction"}
    attrs = if table, do: Map.put(attrs, "db.collection.name", to_string(table)), else: attrs
    name = if table, do: "transaction #{table}", else: "transaction"

    Tracer.with_span name, %{kind: :client, attributes: attrs} do
      res = :mnesia.transaction(fun)

      with {:aborted, reason} <- res do
        Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
        Tracer.set_attribute("error.type", "aborted")
      end

      res
    end
  end
end
