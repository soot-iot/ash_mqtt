defmodule Mix.Tasks.AshMqtt.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.AshMqtt.Install.info([], nil)
      assert info.group == :ash_mqtt
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
    end
  end

  describe "broker config directory" do
    test "creates priv/broker/.gitkeep" do
      test_project(files: %{})
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> assert_creates("priv/broker/.gitkeep")
    end
  end

  describe "formatter" do
    test "imports the ash_mqtt formatter rules" do
      test_project(files: %{})
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:ash_mqtt]
      """)
    end
  end

  describe "config" do
    test "sets :ash_mqtt, :broker_config_dir in config.exs" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("ash_mqtt.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ "ash_mqtt"
      assert diff =~ "broker_config_dir"
      assert diff =~ "priv/broker"
    end
  end

  describe "idempotency" do
    test "running the installer twice leaves the formatter unchanged" do
      test_project(files: %{})
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> assert_unchanged(".formatter.exs")
    end

    test "running the installer twice leaves config.exs unchanged" do
      test_project(files: %{})
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("ash_mqtt.install", [])
      |> assert_unchanged("config/config.exs")
    end
  end

  describe "next-steps notice" do
    test "always emits an ash_mqtt installed notice" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("ash_mqtt.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "ash_mqtt installed"))
    end
  end
end
