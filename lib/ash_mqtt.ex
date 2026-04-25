defmodule AshMqtt do
  @moduledoc """
  MQTT as an Ash transport.

  Two layers, used together or independently:

    * **Resource extension** (`AshMqtt.Resource`) — declare topic patterns,
      QoS, retain, payload format, and ACL policy on an Ash resource. The
      declarations compile to broker-specific config (Mosquitto ACL files,
      EMQX REST API JSON) via `AshMqtt.BrokerConfig`.
    * **Shadow extension** (`AshMqtt.Shadow`) — a thin DSL that expands a
      base topic into the four conventional shadow topics
      (`desired`, `reported`, `delta`, `get`) following the AWS / Azure
      convention so existing tooling and devices interop.

  Topic patterns use `:variable` placeholders. The renderers translate
  these to broker-native template syntax (`%c` for cert CN in Mosquitto,
  `${clientid}` in EMQX, etc.) per `AshMqtt.Topic`.
  """

  @typedoc "An MQTT topic pattern with `:variable` placeholders, e.g. `tenants/:tenant_id/devices/:device_id/up`."
  @type pattern :: String.t()
end
