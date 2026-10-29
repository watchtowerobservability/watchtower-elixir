defmodule Watchtower.MixProject do
  use Mix.Project

  def project do
    [
      app: :watchtower,
      version: "0.1.0",
      elixir: "~> 1.15",
      deps: deps(),
      description: "Thin Watchtower distribution over OpenTelemetry Erlang/Elixir",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/watchtowerobservability/watchtower-elixir"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:telemetry, "~> 1.0"},
      {:plug, "~> 1.16", optional: true},
      {:oban, "~> 2.17", optional: true}
    ]
  end
end
