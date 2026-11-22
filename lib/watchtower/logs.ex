defmodule Watchtower.Logs do
  @moduledoc """
  Elixir `Logger` / Erlang `:logger` events as OTLP log records, through the OTel Erlang logs SDK
  (`:otel_log_handler` from `opentelemetry_experimental`). Records carry the trace and span ids
  that `opentelemetry_api` keeps in the process logger metadata. Install once at application start,
  after `Watchtower.put_config/1`:

      Watchtower.Logs.install(Watchtower.Config.from_env("shop"))

  A no-op returning `:ok` when logs are off (`WATCHTOWER_LOGS=off`).
  """

  @handler :watchtower_otlp_logs

  @doc "Adds the OTLP log handler at `level` (default `:info`)."
  def install(%Watchtower.Config{} = c, level \\ :info) do
    if c.logs do
      :logger.add_handler(@handler, :otel_log_handler, handler_config(c, level))
    else
      :ok
    end
  end

  @doc "Removes the handler."
  def uninstall, do: :logger.remove_handler(@handler)

  @doc false
  def handler_config(c, level) do
    %{
      level: level,
      config: %{
        exporter: Watchtower.Config.signal_exporter(c, :logs),
        scheduled_delay_ms: env_int("OTEL_BLRP_SCHEDULE_DELAY", 1_000),
        exporting_timeout_ms: env_int("OTEL_BLRP_EXPORT_TIMEOUT", 30_000)
      }
    }
  end

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "")) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end
end
