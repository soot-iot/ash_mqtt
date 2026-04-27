defmodule AshMqtt.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ash_mqtt,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :public_key, :crypto, :ssl],
        plt_core_path: "priv/plts",
        plt_local_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters?: true
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "MQTT as an Ash transport: topic DSL, broker config generation, action invocation."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end

  defp aliases do
    [
      format: "format --migrate",
      credo: "credo --strict"
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:spark, "~> 2.6"},
      {:jason, "~> 1.4"},
      # Optional: pulled in only when the operator wants the runtime
      # client. The DSL + broker-config generators don't need it.
      {:emqtt, "~> 1.14", optional: true},
      {:igniter, "~> 0.6", optional: true},

      # Dev / test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
    ]
  end
end
