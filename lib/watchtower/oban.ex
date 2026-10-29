defmodule Watchtower.Oban do
  @moduledoc """
  Captures failed Oban jobs. Call `Watchtower.Oban.attach()` at application start; job spans come
  from `opentelemetry_oban` (`OpentelemetryOban.setup()`), this adds the exception event.
  """

  def attach do
    :telemetry.attach(
      "watchtower-oban",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event(_event, _measure, %{job: job} = meta, _cfg) do
    kind = Map.get(meta, :kind, :error)
    stack = Map.get(meta, :stacktrace, [])

    Watchtower.capture_exception(kind, Map.get(meta, :reason), stack, [
      {"oban.worker", job.worker},
      {"oban.queue", job.queue},
      {"oban.attempt", job.attempt}
    ])
  end
end
