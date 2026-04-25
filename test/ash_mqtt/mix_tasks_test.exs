defmodule AshMqtt.MixTasksTest do
  use ExUnit.Case, async: false

  @tmp Path.join(System.tmp_dir!(), "ash_mqtt_mix_tasks_test")

  setup do
    File.rm_rf!(@tmp)
    File.mkdir_p!(@tmp)
    on_exit(fn -> File.rm_rf!(@tmp) end)
    :ok
  end

  describe "mix ash_mqtt.gen.mosquitto_acl" do
    test "writes an ACL file from --resource arguments" do
      out = Path.join(@tmp, "mosquitto.acl")

      Mix.Tasks.AshMqtt.Gen.MosquittoAcl.run([
        "--out",
        out,
        "--resource",
        "AshMqtt.Test.Fixtures.Device",
        "--resource",
        "AshMqtt.Test.Fixtures.DeviceShadow"
      ])

      body = File.read!(out)
      assert body =~ "pattern read tenants/%u/devices/%c/cmd"
      assert body =~ "pattern read tenants/%u/devices/%c/shadow/desired"
    end

    test "errors out without --resource" do
      out = Path.join(@tmp, "x.acl")

      assert_raise Mix.Error, fn ->
        Mix.Tasks.AshMqtt.Gen.MosquittoAcl.run(["--out", out])
      end
    end
  end

  describe "mix ash_mqtt.gen.emqx_config" do
    test "writes a JSON bundle that decodes back to {acl, rules}" do
      out = Path.join(@tmp, "emqx.json")

      Mix.Tasks.AshMqtt.Gen.EmqxConfig.run([
        "--out",
        out,
        "--resource",
        "AshMqtt.Test.Fixtures.Device"
      ])

      assert {:ok, %{"acl" => acl, "rules" => rules}} = Jason.decode(File.read!(out))
      assert is_list(acl) and acl != []
      assert is_list(rules)
    end
  end
end
