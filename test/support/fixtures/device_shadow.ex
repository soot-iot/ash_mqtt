defmodule AshMqtt.Test.Fixtures.DeviceShadow do
  @moduledoc false

  use Ash.Resource,
    domain: AshMqtt.Test.Fixtures.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshMqtt.Shadow]

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :destroy, :create]
  end

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
