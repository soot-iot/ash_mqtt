defmodule AshMqtt.Runtime.Message do
  @moduledoc """
  An MQTT 5 message in transit.

  The runtime uses this struct in both directions: client publish (the
  fields the operator supplies) and incoming message (what the
  transport hands back). Only MQTT 5 features the runtime needs are
  modeled — subscribers should treat unrecognised properties as
  pass-through.
  """

  defstruct [
    :topic,
    :payload,
    :qos,
    :retain,
    :content_type,
    :response_topic,
    :correlation_data,
    :user_properties
  ]

  @type t :: %__MODULE__{
          topic: String.t(),
          payload: binary(),
          qos: 0 | 1 | 2 | nil,
          retain: boolean() | nil,
          content_type: String.t() | nil,
          response_topic: String.t() | nil,
          correlation_data: binary() | nil,
          user_properties: %{required(String.t()) => String.t()} | nil
        }

  @doc "Build a message from a publish call."
  @spec new(String.t(), binary(), keyword()) :: t()
  def new(topic, payload, opts \\ []) do
    %__MODULE__{
      topic: topic,
      payload: payload,
      qos: Keyword.get(opts, :qos, 0),
      retain: Keyword.get(opts, :retain, false),
      content_type: Keyword.get(opts, :content_type),
      response_topic: Keyword.get(opts, :response_topic),
      correlation_data: Keyword.get(opts, :correlation_data),
      user_properties: Keyword.get(opts, :user_properties)
    }
  end
end
