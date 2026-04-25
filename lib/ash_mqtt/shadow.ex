defmodule AshMqtt.Shadow do
  @moduledoc """
  Ash resource extension that adds an `mqtt_shadow do … end` section.

  Generates the four conventional shadow topics under a base pattern,
  matching the AWS IoT / Azure IoT shape so existing tooling and devices
  interop.

  ## Surface

      defmodule MyApp.Device.Shadow do
        use Ash.Resource, extensions: [AshMqtt.Shadow]

        mqtt_shadow do
          base "tenants/:tenant_id/devices/:device_id/shadow"
          as :device_shadow
          qos 1
          retain true
          payload_format :json
          acl :tenant_isolated

          desired_attributes [:led, :sample_rate, :firmware_version]
          reported_attributes [:led, :sample_rate, :firmware_version, :uptime_s]
        end
      end

  Use `AshMqtt.Shadow.Info.topics/1` to get the four expanded topics for
  use with `AshMqtt.BrokerConfig` (the renderers know to walk both
  `AshMqtt.Resource` and `AshMqtt.Shadow` declarations).
  """

  @declaration %Spark.Dsl.Section{
    name: :mqtt_shadow,
    describe: "Device-shadow topic conventions for this resource.",
    schema: [
      base: [
        type: :string,
        required: true,
        doc:
          "Base pattern; the four shadow topics (desired/reported/delta/get) are derived from it."
      ],
      as: [
        type: :atom,
        doc: "Short name to refer to the shadow set in code or other declarations."
      ],
      qos: [type: {:one_of, [0, 1, 2]}, default: 1],
      retain: [type: :boolean, default: true],
      payload_format: [
        type: {:one_of, [:json, :cbor, :protobuf]},
        default: :json
      ],
      acl: [
        type:
          {:one_of, [:tenant_isolated, :device_owned, :public_subscribe, :public_publish]},
        default: :tenant_isolated
      ],
      desired_attributes: [
        type: {:list, :atom},
        default: [],
        doc: "Non-authoritative hint listing attributes the backend may set."
      ],
      reported_attributes: [
        type: {:list, :atom},
        default: [],
        doc: "Non-authoritative hint listing attributes the device may report."
      ]
    ]
  }

  use Spark.Dsl.Extension, sections: [@declaration]
end
