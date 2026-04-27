defmodule AshMqtt.Test.Fixtures.Device do
  @moduledoc false

  use Ash.Resource,
    domain: AshMqtt.Test.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMqtt.Resource]

  attributes do
    uuid_primary_key :id
    attribute :tenant_id, :string, public?: true
    attribute :serial, :string, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:tenant_id, :serial]]

    update :reboot do
      accept []
      change set_attribute(:serial, expr(serial))
    end
  end

  mqtt do
    qos(1)
    retain(false)
    payload_format(:json)
    acl(:tenant_isolated)

    topic("tenants/:tenant_id/devices/:device_id/cmd",
      as: :cmd_in,
      direction: :inbound
    )

    topic("tenants/:tenant_id/devices/:device_id/up",
      as: :events_out,
      direction: :outbound,
      qos: 0
    )

    topic("tenants/:tenant_id/devices/:device_id/state",
      as: :state,
      direction: :outbound,
      retain: true,
      payload_format: :cbor
    )

    action :reboot, topic: "tenants/:tenant_id/devices/:device_id/cmd/reboot"

    action :read_config,
      topic: "tenants/:tenant_id/devices/:device_id/cmd/read_config",
      reply: true,
      timeout: 3_000
  end
end

defmodule AshMqtt.Test.Fixtures.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshMqtt.Test.Fixtures.Device
    resource AshMqtt.Test.Fixtures.DeviceShadow
  end
end
