defmodule AshMqtt.Resource.Action do
  @moduledoc """
  Compile-time record for an Ash action exposed at an MQTT topic.

  `reply: true` declares a request/response interaction over MQTT 5
  features (response topics, correlation data, content type). The runtime
  client handles correlation; this struct only carries the declaration.

  `timeout` is in milliseconds and is used by the runtime for
  `reply: true` actions to bound how long it waits for a response.
  """

  defstruct [
    :name,
    :topic,
    :reply,
    :timeout,
    :payload_format,
    :qos,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          topic: String.t(),
          reply: boolean() | nil,
          timeout: pos_integer() | nil,
          payload_format: AshMqtt.Resource.Topic.payload_format() | nil,
          qos: 0 | 1 | 2 | nil
        }
end
