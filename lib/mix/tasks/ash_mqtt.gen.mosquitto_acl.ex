defmodule Mix.Tasks.AshMqtt.Gen.MosquittoAcl do
  @shortdoc "Render a Mosquitto ACL file from one or more Ash resources"

  @moduledoc """
  Render an ACL file from a list of resources that use `AshMqtt.Resource`
  and/or `AshMqtt.Shadow`.

      mix ash_mqtt.gen.mosquitto_acl --out priv/broker/mosquitto.acl \\
                                    --resource MyApp.Device \\
                                    --resource MyApp.Device.Shadow

  Pass `--resource` once per resource. Modules must be loadable —
  `Mix.Task.run("app.start")` is invoked for you.
  """

  use Mix.Task

  @switches [out: :string, resource: [:string, :keep]]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    out = Keyword.fetch!(opts, :out)
    resources = opts |> Keyword.get_values(:resource) |> Enum.map(&load_module/1)

    if resources == [] do
      Mix.raise("at least one --resource <module> is required")
    end

    File.mkdir_p!(Path.dirname(out))
    File.write!(out, AshMqtt.BrokerConfig.Mosquitto.render(resources))
    Mix.shell().info("wrote #{out}")
  end

  defp load_module(name) do
    mod = Module.concat([name])
    Code.ensure_loaded!(mod)
    mod
  end
end
