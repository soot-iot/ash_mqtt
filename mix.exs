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
      package: package()
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

  defp deps do
    [
      {:ash, "~> 3.24"},
      {:spark, "~> 2.6"},
      {:jason, "~> 1.4"}
    ]
  end
end
