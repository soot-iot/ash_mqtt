defmodule AshMqtt.BrokerConfig.EMQXTest do
  use ExUnit.Case, async: true

  alias AshMqtt.BrokerConfig.EMQX
  alias AshMqtt.Test.Fixtures.{Device, DeviceShadow}

  describe "render/2" do
    test "produces an :acl key with one rule per topic" do
      %{acl: acl} = EMQX.render([Device])
      assert is_list(acl)

      # 3 topics + 2 actions + 1 reply subtopic = 6 ACL entries.
      assert length(acl) == 6

      # Every entry has the standard EMQX rule keys.
      Enum.each(acl, fn entry ->
        assert Map.has_key?(entry, :permission)
        assert Map.has_key?(entry, :action)
        assert Map.has_key?(entry, :topic)
      end)
    end

    test "tenant_isolated rules carry username: ${username}" do
      %{acl: acl} = EMQX.render([Device])

      assert Enum.all?(acl, &(&1[:username] == "${username}"))
    end

    test "direction translates to the EMQX action atom" do
      %{acl: acl} = EMQX.render([Device])
      by_topic = Map.new(acl, &{&1.topic, &1.action})

      assert by_topic["tenants/${username}/devices/${clientid}/cmd"] == "subscribe"
      assert by_topic["tenants/${username}/devices/${clientid}/up"] == "publish"
      assert by_topic["tenants/${username}/devices/${clientid}/cmd/reboot"] == "all"
    end

    test "produces a :rules entry per non-opaque topic with a SQL body" do
      %{rules: rules} = EMQX.render([Device])
      assert rules != []

      Enum.each(rules, fn rule ->
        assert rule.enable == true
        assert rule.sql =~ ~r/^SELECT \* FROM "/
      end)
    end

    test "skips :opaque payload formats from the rules" do
      defmodule OpaqueResource do
        use Ash.Resource,
          domain: AshMqtt.Test.Fixtures.Domain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshMqtt.Resource]

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read, :destroy, :create]
        end

        mqtt do
          payload_format(:opaque)
          topic("blob/:device_id", as: :blob)
        end
      end

      %{rules: rules} = EMQX.render([OpaqueResource])
      assert rules == []
    end

    test "shadow topics are merged into the EMQX bundle" do
      %{acl: acl} = EMQX.render([DeviceShadow])
      topics = Enum.map(acl, & &1.topic)

      assert "tenants/${username}/devices/${clientid}/shadow/desired" in topics
      assert "tenants/${username}/devices/${clientid}/shadow/reported" in topics
      assert "tenants/${username}/devices/${clientid}/shadow/delta" in topics
      assert "tenants/${username}/devices/${clientid}/shadow/get" in topics
    end
  end

  describe "to_json/2" do
    test "is valid JSON and round-trips through Jason" do
      json = EMQX.to_json([Device])
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
      assert is_list(decoded["acl"])
      assert is_list(decoded["rules"])
    end
  end
end
