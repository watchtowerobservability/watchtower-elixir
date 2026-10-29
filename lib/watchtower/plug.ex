if Code.ensure_loaded?(Plug) do
  defmodule Watchtower.Plug do
    @moduledoc """
    Captures exceptions raised in a Plug pipeline or Phoenix endpoint:

        defmodule MyAppWeb.Endpoint do
          use Phoenix.Endpoint, otp_app: :my_app
          use Watchtower.Plug
        end

    Request tracing itself comes from `opentelemetry_phoenix` / `opentelemetry_cowboy`; this adds
    exception events on the request span. The exception is re-raised, so error pages are unchanged.
    """

    defmacro __using__(_opts) do
      quote do
        use Plug.ErrorHandler

        @impl Plug.ErrorHandler
        def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
          Watchtower.capture_exception(kind, reason, stack, [
            {"http.request.method", conn.method},
            {"url.path", conn.request_path}
          ])

          conn
        end
      end
    end
  end
end
