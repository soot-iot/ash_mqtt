defmodule AshMqtt.BrokerConfigTest do
  use ExUnit.Case, async: true

  alias AshMqtt.BrokerConfig
  alias AshMqtt.Test.Fixtures.{Device, DeviceShadow}

  describe "extension detection" do
    test "uses_resource_extension? is true for AshMqtt.Resource users" do
      assert BrokerConfig.uses_resource_extension?(Device)
      refute BrokerConfig.uses_resource_extension?(DeviceShadow)
    end

    test "uses_shadow_extension? is true for AshMqtt.Shadow users" do
      assert BrokerConfig.uses_shadow_extension?(DeviceShadow)
      refute BrokerConfig.uses_shadow_extension?(Device)
    end
  end

  describe "topics/1" do
    test "merges base + shadow topics for resources that use both surfaces" do
      assert length(BrokerConfig.topics(Device)) == 3
      assert length(BrokerConfig.topics(DeviceShadow)) == 4
    end

    test "returns [] for a resource that uses neither" do
      defmodule Plain do
        use Ash.Resource,
          domain: AshMqtt.Test.Fixtures.Domain,
          data_layer: Ash.DataLayer.Ets

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy, :create]
        end
      end

      assert BrokerConfig.topics(Plain) == []
      refute BrokerConfig.uses_resource_extension?(Plain)
      refute BrokerConfig.uses_shadow_extension?(Plain)
    end
  end

  describe "actions/1" do
    test "returns the resource's mqtt actions" do
      assert length(BrokerConfig.actions(Device)) == 2
    end

    test "returns [] for a shadow-only resource" do
      assert BrokerConfig.actions(DeviceShadow) == []
    end
  end

  describe "topics_for_all/1" do
    test "flattens topics across multiple resources" do
      all = BrokerConfig.topics_for_all([Device, DeviceShadow])
      assert length(all) == 7
    end
  end
end
