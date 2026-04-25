defmodule AshMqtt.TopicTest do
  use ExUnit.Case, async: true
  doctest AshMqtt.Topic

  describe "variables/1" do
    test "extracts placeholders in left-to-right order" do
      assert AshMqtt.Topic.variables("a/:x/b/:y/c") == [:x, :y]
    end

    test "returns [] when there are no placeholders" do
      assert AshMqtt.Topic.variables("a/b/c") == []
    end
  end

  describe "render/2" do
    test ":mosquitto substitutes %u/%c for tenant_id/device_id and + for the rest" do
      assert AshMqtt.Topic.render(
               "tenants/:tenant_id/devices/:device_id/streams/:stream/up",
               :mosquitto
             ) == "tenants/%u/devices/%c/streams/+/up"
    end

    test ":emqx substitutes ${username}/${clientid} for tenant_id/device_id" do
      assert AshMqtt.Topic.render(
               "tenants/:tenant_id/devices/:device_id/up",
               :emqx
             ) == "tenants/${username}/devices/${clientid}/up"
    end
  end

  describe "match_filter/2" do
    test "every variable becomes a single-level wildcard" do
      assert AshMqtt.Topic.match_filter("tenants/:tenant_id/+/up", :emqx) ==
               "tenants/+/+/up"
    end
  end
end
