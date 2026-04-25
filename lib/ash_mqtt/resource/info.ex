defmodule AshMqtt.Resource.Info do
  @moduledoc """
  Introspection helpers for the `mqtt do … end` section.

      AshMqtt.Resource.Info.topics(MyApp.Device)
      AshMqtt.Resource.Info.actions(MyApp.Device)
      AshMqtt.Resource.Info.mqtt_qos!(MyApp.Device)

  `Spark.InfoGenerator` exposes section options as
  `mqtt_qos/1`, `mqtt_retain/1`, `mqtt_payload_format/1`, `mqtt_acl/1`
  (with `!` variants that raise on unset). The single `mqtt/1` getter
  returns every entity in the section; `topics/1` and `actions/1` filter
  it by struct type.
  """

  use Spark.InfoGenerator,
    extension: AshMqtt.Resource,
    sections: [:mqtt]

  alias AshMqtt.Resource.{Action, Topic}

  @doc "All `topic` entities declared on the resource."
  @spec topics(module()) :: [Topic.t()]
  def topics(resource) do
    resource |> mqtt() |> Enum.filter(&match?(%Topic{}, &1))
  end

  @doc "All `action` entities declared on the resource."
  @spec actions(module()) :: [Action.t()]
  def actions(resource) do
    resource |> mqtt() |> Enum.filter(&match?(%Action{}, &1))
  end

  @doc "Resolve a topic-or-action's effective QoS, falling back to the section default."
  @spec effective_qos(module(), Topic.t() | Action.t()) :: 0 | 1 | 2
  def effective_qos(_resource, %{qos: qos}) when qos in [0, 1, 2], do: qos
  def effective_qos(resource, _), do: mqtt_qos!(resource)

  @doc "Resolve a topic's effective retain flag."
  @spec effective_retain(module(), Topic.t()) :: boolean()
  def effective_retain(_resource, %Topic{retain: retain}) when is_boolean(retain), do: retain
  def effective_retain(resource, _), do: mqtt_retain!(resource)

  @doc "Resolve a topic-or-action's effective payload format."
  @spec effective_payload_format(module(), Topic.t() | Action.t()) :: atom()
  def effective_payload_format(_resource, %{payload_format: fmt}) when not is_nil(fmt), do: fmt
  def effective_payload_format(resource, _), do: mqtt_payload_format!(resource)

  @doc "Resolve a topic's effective ACL policy."
  @spec effective_acl(module(), Topic.t()) :: atom()
  def effective_acl(_resource, %Topic{acl: acl}) when not is_nil(acl), do: acl
  def effective_acl(resource, _), do: mqtt_acl!(resource)

  @doc "Look up a topic by its `as:` short name. Returns nil when missing."
  @spec topic_by_name(module(), atom()) :: Topic.t() | nil
  def topic_by_name(resource, name) when is_atom(name) do
    resource |> topics() |> Enum.find(&(&1.as == name))
  end

  @doc "Look up an action declaration by name. Returns nil when missing."
  @spec action(module(), atom()) :: Action.t() | nil
  def action(resource, name) when is_atom(name) do
    resource |> actions() |> Enum.find(&(&1.name == name))
  end
end
