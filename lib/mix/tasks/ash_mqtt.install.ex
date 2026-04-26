defmodule Mix.Tasks.AshMqtt.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs the ash_mqtt MQTT-as-Ash-transport library into a Phoenix project"
  end

  def example do
    "mix igniter.install ash_mqtt"
  end

  def long_doc do
    """
    #{short_doc()}

    Imports the `ash_mqtt` formatter rules, creates the `priv/broker/`
    output directory used by `mix soot.broker.gen_config`, and wires the
    `:broker_config_dir` application config so the generator knows where
    to write the rendered broker artifacts. Composed by `mix soot.install`;
    can also be run standalone.

    `ash_mqtt` is a broker-side concern — it generates `mosquitto.conf`
    / `emqx.conf` / ACL files from the MQTT DSL declared in the
    operator's resources. The installer therefore does not patch any
    Phoenix routers; the MQTT listener lives in the broker the operator
    deploys alongside their app.

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

      * `--example` — same shape as the rest of the Soot installers;
        currently a no-op for `ash_mqtt` since the broker config is only
        meaningful once the operator has declared MQTT topics on their
        Ash resources.
      * `--yes` — answer yes to dependency-fetching prompts.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshMqtt.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @broker_config_dir "priv/broker"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_mqtt,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: [],
        schema: [example: :boolean, yes: :boolean],
        defaults: [example: false, yes: false],
        aliases: [y: :yes, e: :example]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_mqtt)
      |> create_broker_config_dir()
      |> configure_broker_config_dir()
      |> note_next_steps()
    end

    defp create_broker_config_dir(igniter) do
      Igniter.create_new_file(
        igniter,
        Path.join(@broker_config_dir, ".gitkeep"),
        "",
        on_exists: :skip
      )
    end

    defp configure_broker_config_dir(igniter) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        :ash_mqtt,
        [:broker_config_dir],
        @broker_config_dir
      )
    end

    defp note_next_steps(igniter) do
      Igniter.add_notice(igniter, """
      ash_mqtt installed.

      The broker-config output directory is `#{@broker_config_dir}/`.
      Once you have declared MQTT topics on your Ash resources, run:

        mix soot.broker.gen_config

      to render `mosquitto.conf` / `emqx.conf` / ACL files into that
      directory. Mount the rendered files into your broker container
      (or symlink them into `/etc/mosquitto/`) to take effect.
      """)
    end
  end
else
  defmodule Mix.Tasks.AshMqtt.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `ash_mqtt.install` requires igniter. Add
      `{:igniter, "~> 0.6"}` to your project deps and try again, or
      invoke via:

          mix igniter.install ash_mqtt

      For more information, see https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
