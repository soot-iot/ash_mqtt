defmodule AshMqtt.Runtime.Transport do
  @moduledoc """
  Behavior every MQTT transport implements.

  The runtime client (`AshMqtt.Runtime.Client`) calls these in the
  abstract; concrete implementations are:

    * `AshMqtt.Runtime.Transport.EMQTT` — production, talks to a real
      broker via the `:emqtt` Erlang client.
    * `AshMqtt.Runtime.Transport.Test` — in-memory; records calls and
      lets tests inject incoming messages.

  ## Responsibilities

  Connect to the broker, publish/subscribe under MQTT 5 semantics, and
  forward incoming messages to the owning process as
  `{:ash_mqtt_msg, %AshMqtt.Runtime.Message{}}`.

  Connect & subscribe semantics are synchronous (`:ok | {:error, _}`).
  Publish is best-effort and asynchronous; QoS-0 returns `:ok` on
  enqueue. Failure modes are transport-specific.
  """

  alias AshMqtt.Runtime.Message

  @typedoc "Opaque transport state; the implementation defines its shape."
  @type state :: any()

  @callback connect(opts :: keyword(), owner :: pid()) :: {:ok, state()} | {:error, term()}

  @callback publish(state(), Message.t()) :: :ok | {:error, term()}

  @callback subscribe(state(), topic_filter :: String.t(), qos :: 0 | 1 | 2) ::
              :ok | {:error, term()}

  @callback unsubscribe(state(), topic_filter :: String.t()) :: :ok | {:error, term()}

  @callback disconnect(state()) :: :ok
end
