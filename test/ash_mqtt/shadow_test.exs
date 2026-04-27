defmodule AshMqtt.ShadowTest do
  use ExUnit.Case, async: true

  alias AshMqtt.Shadow.Info
  alias AshMqtt.Test.Fixtures.{Device, DeviceShadow}

  describe "declared?/1" do
    test "true for resources that opt in" do
      assert Info.declared?(DeviceShadow)
    end

    test "false for resources that don't" do
      refute Info.declared?(Device)
    end
  end

  describe "topics/1" do
    setup do
      {:ok, topics: Info.topics(DeviceShadow)}
    end

    test "expands to exactly four conventional topics", %{topics: topics} do
      assert length(topics) == 4

      patterns = Enum.map(topics, & &1.pattern) |> Enum.sort()

      assert patterns == [
               "tenants/:tenant_id/devices/:device_id/shadow/delta",
               "tenants/:tenant_id/devices/:device_id/shadow/desired",
               "tenants/:tenant_id/devices/:device_id/shadow/get",
               "tenants/:tenant_id/devices/:device_id/shadow/reported"
             ]
    end

    test "directions follow the AWS/Azure shadow convention", %{topics: topics} do
      by_pattern = Map.new(topics, &{&1.pattern, &1.direction})

      # Backend publishes desired and delta and responds to get;
      # device publishes reported.
      assert by_pattern["tenants/:tenant_id/devices/:device_id/shadow/desired"] == :inbound
      assert by_pattern["tenants/:tenant_id/devices/:device_id/shadow/delta"] == :inbound
      assert by_pattern["tenants/:tenant_id/devices/:device_id/shadow/get"] == :inbound
      assert by_pattern["tenants/:tenant_id/devices/:device_id/shadow/reported"] == :outbound
    end

    test "every topic carries the section-level qos/retain/payload_format/acl", %{topics: topics} do
      assert Enum.all?(topics, &(&1.qos == 1))
      assert Enum.all?(topics, &(&1.retain == true))
      assert Enum.all?(topics, &(&1.payload_format == :json))
      assert Enum.all?(topics, &(&1.acl == :tenant_isolated))
    end

    test "as: prefix is honoured in the topic short names", %{topics: topics} do
      names = Enum.map(topics, & &1.as) |> Enum.sort()

      assert names == [
               :device_shadow_delta,
               :device_shadow_desired,
               :device_shadow_get,
               :device_shadow_reported
             ]
    end
  end

  describe "DSL parse-time validation" do
    test "rejects missing base" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule MissingBase do
          use Ash.Resource,
            domain: AshMqtt.Test.Fixtures.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshMqtt.Shadow]

          attributes do
            uuid_primary_key :id
          end

          mqtt_shadow do
            qos(1)
          end
        end
      end
    end
  end
end
