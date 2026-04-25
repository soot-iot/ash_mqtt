defmodule AshMqtt.Resource.Topic do
  @moduledoc """
  Compile-time data for a single `topic` declaration inside an `mqtt do …`
  section.

  `pattern` uses `:variable` placeholders. `direction` constrains who is
  allowed to publish vs. subscribe in the rendered ACLs.

  Per-topic `qos`, `retain`, `payload_format`, and `acl` overrides take
  precedence over the section-level defaults.
  """

  defstruct [
    :pattern,
    :as,
    :direction,
    :qos,
    :retain,
    :payload_format,
    :acl,
    __spark_metadata__: nil
  ]

  @type direction :: :inbound | :outbound | :bidirectional
  @type payload_format :: :json | :cbor | :arrow_ipc | :protobuf | :opaque
  @type acl :: :tenant_isolated | :device_owned | :public_subscribe | :public_publish

  @type t :: %__MODULE__{
          pattern: String.t(),
          as: atom() | nil,
          direction: direction() | nil,
          qos: 0 | 1 | 2 | nil,
          retain: boolean() | nil,
          payload_format: payload_format() | nil,
          acl: acl() | nil
        }
end
