defmodule Mix.Tasks.AshMqtt.Gen.EmqxConfig do
  @shortdoc "Render EMQX REST-API JSON for ACL + rules from Ash resources"

  @moduledoc """
  Render the EMQX configuration bundle (`{acl, rules}`) for a list of
  resources and write it to disk as JSON.

      mix ash_mqtt.gen.emqx_config --out priv/broker/emqx.json \\
                                  --resource MyApp.Device \\
                                  --resource MyApp.Device.Shadow

  Pushing the bundle to a live EMQX node is a separate operator step:
  `POST /api/v5/authorization/sources` for `acl`, `POST /api/v5/rules`
  for `rules`.
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
    File.write!(out, AshMqtt.BrokerConfig.EMQX.to_json(resources))
    Mix.shell().info("wrote #{out}")
  end

  defp load_module(name) do
    mod = Module.concat([name])
    Code.ensure_loaded!(mod)
    mod
  end
end
