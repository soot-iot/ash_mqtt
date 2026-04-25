defmodule AshMqtt.ResourceTest do
  use ExUnit.Case, async: true

  alias AshMqtt.Resource.Info
  alias AshMqtt.Test.Fixtures.Device

  describe "section defaults" do
    test "qos, retain, payload_format, acl come back via the InfoGenerator" do
      assert Info.mqtt_qos!(Device) == 1
      assert Info.mqtt_retain!(Device) == false
      assert Info.mqtt_payload_format!(Device) == :json
      assert Info.mqtt_acl!(Device) == :tenant_isolated
    end
  end

  describe "topics/1 + actions/1" do
    test "topics returns one struct per declaration in source order" do
      topics = Info.topics(Device)
      assert Enum.map(topics, & &1.as) == [:cmd_in, :events_out, :state]

      assert Enum.find(topics, &(&1.as == :cmd_in)).direction == :inbound
      assert Enum.find(topics, &(&1.as == :events_out)).direction == :outbound
      assert Enum.find(topics, &(&1.as == :state)).retain == true
    end

    test "actions returns the declared action structs with reply/timeout" do
      actions = Info.actions(Device)
      assert length(actions) == 2

      reboot = Enum.find(actions, &(&1.name == :reboot))
      assert reboot.reply == false
      assert reboot.timeout == 5_000

      read_config = Enum.find(actions, &(&1.name == :read_config))
      assert read_config.reply == true
      assert read_config.timeout == 3_000
    end
  end

  describe "effective_*/2" do
    test "topic-level qos override beats the section default" do
      events_out = Info.topic_by_name(Device, :events_out)
      assert events_out.qos == 0
      assert Info.effective_qos(Device, events_out) == 0
    end

    test "missing topic-level value falls back to the section default" do
      cmd_in = Info.topic_by_name(Device, :cmd_in)
      assert is_nil(cmd_in.qos)
      assert Info.effective_qos(Device, cmd_in) == 1
    end

    test "topic-level payload_format override is respected" do
      state = Info.topic_by_name(Device, :state)
      assert Info.effective_payload_format(Device, state) == :cbor
    end

    test "topic-level retain override is respected" do
      state = Info.topic_by_name(Device, :state)
      assert Info.effective_retain(Device, state) == true
    end

    test "topic-level acl falls back when not set" do
      cmd_in = Info.topic_by_name(Device, :cmd_in)
      assert is_nil(cmd_in.acl)
      assert Info.effective_acl(Device, cmd_in) == :tenant_isolated
    end
  end

  describe "look-up helpers" do
    test "topic_by_name/2 returns nil when nothing matches" do
      assert is_nil(Info.topic_by_name(Device, :nope))
    end

    test "action/2 returns nil when nothing matches" do
      assert is_nil(Info.action(Device, :nope))
    end
  end

  describe "DSL parse-time validation" do
    test "rejects an unknown payload_format atom" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule BadResource do
          use Ash.Resource,
            domain: AshMqtt.Test.Fixtures.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshMqtt.Resource]

          attributes do
            uuid_primary_key :id
          end

          mqtt do
            payload_format :nonexistent
            topic "a/b", as: :a
          end
        end
      end
    end

    test "rejects an unknown qos value" do
      assert_raise Spark.Error.DslError, fn ->
        defmodule BadQos do
          use Ash.Resource,
            domain: AshMqtt.Test.Fixtures.Domain,
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshMqtt.Resource]

          attributes do
            uuid_primary_key :id
          end

          mqtt do
            qos 7
            topic "a/b", as: :a
          end
        end
      end
    end
  end
end
