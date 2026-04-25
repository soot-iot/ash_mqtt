defmodule AshMqtt.BrokerConfig do
  @moduledoc """
  Unified surface for collecting topics + actions across the
  `AshMqtt.Resource` and `AshMqtt.Shadow` extensions.

  Each broker-specific renderer (`AshMqtt.BrokerConfig.Mosquitto`,
  `AshMqtt.BrokerConfig.EMQX`) goes through this module so a resource
  that mixes both DSLs is rendered the same way as two separate
  resources, one per DSL.
  """

  alias AshMqtt.Resource.{Action, Topic}

  @doc "Every topic declared on a resource via either DSL."
  @spec topics(module()) :: [Topic.t()]
  def topics(resource) do
    base_topics(resource) ++ shadow_topics(resource)
  end

  @doc "Every action declared on a resource via the resource DSL."
  @spec actions(module()) :: [Action.t()]
  def actions(resource) do
    if uses_resource_extension?(resource) do
      AshMqtt.Resource.Info.actions(resource)
    else
      []
    end
  end

  @doc "Every topic across a list of resources, flattened."
  @spec topics_for_all([module()]) :: [Topic.t()]
  def topics_for_all(resources) when is_list(resources) do
    Enum.flat_map(resources, &topics/1)
  end

  @doc "Whether the resource opted into the `mqtt do …` DSL."
  @spec uses_resource_extension?(module()) :: boolean()
  def uses_resource_extension?(resource), do: has_extension?(resource, AshMqtt.Resource)

  @doc "Whether the resource opted into the `mqtt_shadow do …` DSL."
  @spec uses_shadow_extension?(module()) :: boolean()
  def uses_shadow_extension?(resource), do: has_extension?(resource, AshMqtt.Shadow)

  defp base_topics(resource) do
    if uses_resource_extension?(resource) do
      AshMqtt.Resource.Info.topics(resource)
    else
      []
    end
  end

  defp shadow_topics(resource) do
    if uses_shadow_extension?(resource) do
      AshMqtt.Shadow.Info.topics(resource)
    else
      []
    end
  end

  defp has_extension?(resource, extension) do
    extensions = Spark.extensions(resource)
    extension in extensions
  rescue
    _ -> false
  end
end
