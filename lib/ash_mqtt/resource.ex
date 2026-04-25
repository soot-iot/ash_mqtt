defmodule AshMqtt.Resource do
  @moduledoc """
  Ash resource extension that adds an `mqtt do … end` section.

  ## Surface

      defmodule MyApp.Device do
        use Ash.Resource, extensions: [AshMqtt.Resource]

        mqtt do
          # Section defaults; topic-level overrides take precedence.
          qos 1
          retain false
          payload_format :json
          acl :tenant_isolated

          topic "tenants/:tenant_id/devices/:device_id/cmd",
            as: :cmd_in,
            direction: :inbound

          topic "tenants/:tenant_id/devices/:device_id/up",
            as: :events_out,
            direction: :outbound

          action :reboot,
            topic: "tenants/:tenant_id/devices/:device_id/cmd/reboot"

          action :read_config,
            topic: "tenants/:tenant_id/devices/:device_id/cmd/read_config",
            reply: true,
            timeout: 5_000
        end
      end

  Use `AshMqtt.Resource.Info` to introspect a resource's MQTT
  declarations at runtime, or `AshMqtt.BrokerConfig` to render
  broker-specific configuration.
  """

  @topic %Spark.Dsl.Entity{
    name: :topic,
    target: AshMqtt.Resource.Topic,
    args: [:pattern],
    schema: [
      pattern: [
        type: :string,
        required: true,
        doc: "The topic pattern. Use `:variable` for placeholders."
      ],
      as: [
        type: :atom,
        doc: "A short name used to refer to this topic from code or other declarations."
      ],
      direction: [
        type: {:one_of, [:inbound, :outbound, :bidirectional]},
        default: :bidirectional,
        doc: "Who is allowed to publish vs. subscribe."
      ],
      qos: [
        type: {:one_of, [0, 1, 2]},
        doc: "Per-topic QoS override. Defaults to the section-level qos."
      ],
      retain: [
        type: :boolean,
        doc: "Per-topic retain override. Defaults to the section-level retain."
      ],
      payload_format: [
        type: {:one_of, [:json, :cbor, :arrow_ipc, :protobuf, :opaque]},
        doc: "Per-topic payload format. Defaults to the section-level payload_format."
      ],
      acl: [
        type:
          {:one_of, [:tenant_isolated, :device_owned, :public_subscribe, :public_publish]},
        doc: "Per-topic ACL override. Defaults to the section-level acl."
      ]
    ]
  }

  @action %Spark.Dsl.Entity{
    name: :action,
    target: AshMqtt.Resource.Action,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The Ash action this MQTT-exposed action corresponds to."
      ],
      topic: [
        type: :string,
        required: true,
        doc: "Topic pattern at which the action is invoked."
      ],
      reply: [
        type: :boolean,
        default: false,
        doc: "If true, the broker generates a response topic per request and the client correlates."
      ],
      timeout: [
        type: :pos_integer,
        default: 5_000,
        doc: "Milliseconds to wait for a reply when `reply: true`."
      ],
      payload_format: [
        type: {:one_of, [:json, :cbor, :arrow_ipc, :protobuf, :opaque]},
        doc: "Payload format for the request and (if applicable) reply body."
      ],
      qos: [
        type: {:one_of, [0, 1, 2]},
        doc: "Per-action QoS override."
      ]
    ]
  }

  @mqtt %Spark.Dsl.Section{
    name: :mqtt,
    describe: "MQTT topic declarations and action exposure for this resource.",
    entities: [@topic, @action],
    schema: [
      qos: [
        type: {:one_of, [0, 1, 2]},
        default: 1,
        doc: "Section-level QoS default."
      ],
      retain: [
        type: :boolean,
        default: false,
        doc: "Section-level retain default."
      ],
      payload_format: [
        type: {:one_of, [:json, :cbor, :arrow_ipc, :protobuf, :opaque]},
        default: :json,
        doc: "Section-level payload format default."
      ],
      acl: [
        type:
          {:one_of, [:tenant_isolated, :device_owned, :public_subscribe, :public_publish]},
        default: :tenant_isolated,
        doc: "Section-level ACL policy default."
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@mqtt]
end
