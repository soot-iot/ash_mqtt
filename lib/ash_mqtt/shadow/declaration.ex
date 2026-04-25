defmodule AshMqtt.Shadow.Declaration do
  @moduledoc """
  Compile-time data for an `mqtt_shadow do … end` block.

  `base` is a topic pattern under which the four conventional shadow
  topics are derived:

      <base>/desired
      <base>/reported
      <base>/delta
      <base>/get

  `desired_attributes` and `reported_attributes` are non-authoritative
  hints for documentation and contract bundles; the wire format is JSON
  by default.
  """

  defstruct [
    :base,
    :as,
    :qos,
    :retain,
    :payload_format,
    :acl,
    desired_attributes: [],
    reported_attributes: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          base: String.t(),
          as: atom() | nil,
          qos: 0 | 1 | 2 | nil,
          retain: boolean() | nil,
          payload_format: AshMqtt.Resource.Topic.payload_format() | nil,
          acl: AshMqtt.Resource.Topic.acl() | nil,
          desired_attributes: [atom()],
          reported_attributes: [atom()]
        }
end
