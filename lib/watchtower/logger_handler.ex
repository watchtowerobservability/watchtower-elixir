defmodule Watchtower.LoggerHandler do
  @moduledoc """
  Erlang `:logger` handler: error-level (and above) events that carry a crash reason or an
  exception are captured on the active span. Install once at application start:

      Watchtower.LoggerHandler.install()
  """

  def install(level \\ :error) do
    :logger.add_handler(:watchtower, __MODULE__, %{level: level})
  end

  # `:logger` callback.
  def log(%{meta: meta} = event, _config) do
    case crash(meta) do
      {kind, reason, stack} -> Watchtower.capture_exception(kind, reason, stack, trace_meta(event))
      nil -> :ok
    end
  rescue
    # A broken handler must never take the logging pipeline down.
    _ -> :ok
  end

  @doc false
  def crash(%{crash_reason: {reason, stack}}) when is_list(stack) do
    case reason do
      %{__exception__: true} -> {:error, reason, stack}
      _ -> {:exit, reason, stack}
    end
  end

  def crash(_), do: nil

  defp trace_meta(%{level: level}), do: [{"log.level", to_string(level)}]
end
