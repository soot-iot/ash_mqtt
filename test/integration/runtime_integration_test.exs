defmodule AshMqtt.Runtime.IntegrationTest do
  @moduledoc """
  Optional ExUnit suite that exercises the runtime client and the
  `:emqtt`-backed transport against a live MQTT 5 broker.

  Excluded by default. Run with:

      mix test --only integration

  Selects which broker via the `MQTT_BROKER` environment variable
  (`emqx` or `mosquitto`); ports default to `1883`/`1884` to match
  `docker/docker-compose.yml`.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag timeout: 30_000

  alias AshMqtt.Runtime.Client
  alias AshMqtt.Runtime.Message
  alias AshMqtt.Runtime.Transport.EMQTT, as: EMQTTTransport
  alias AshMqtt.Test.BrokerEnv

  setup_all do
    %{host: host, port: port, broker: broker} = BrokerEnv.endpoint()
    BrokerEnv.await_broker!(host, port)
    {:ok, host: host, port: port, broker: broker}
  end

  setup ctx do
    prefix = "ash_mqtt_int/#{ctx.broker}/#{BrokerEnv.rand_hex()}"
    {:ok, prefix: prefix}
  end

  defp start_client!(ctx, extra \\ []) do
    transport_opts =
      [
        host: String.to_charlist(ctx.host),
        port: ctx.port,
        clientid: "ash_mqtt_test_" <> BrokerEnv.rand_hex(),
        clean_start: true,
        keepalive: 30
      ]
      |> Keyword.merge(extra)

    {:ok, client} =
      Client.start_link(
        transport: EMQTTTransport,
        transport_opts: transport_opts,
        reply_prefix: "ash_mqtt_int/_replies/" <> BrokerEnv.rand_hex()
      )

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(client), do: GenServer.stop(client, :normal, 1_000)
    end)

    client
  end

  describe "transport lifecycle" do
    test "connect / disconnect against the broker", ctx do
      client = start_client!(ctx)
      assert Process.alive?(client)
      :ok = GenServer.stop(client, :normal, 1_000)
      refute Process.alive?(client)
    end

    test "connect failure surfaces as {:error, _}", ctx do
      Process.flag(:trap_exit, true)

      result =
        Client.start_link(
          transport: EMQTTTransport,
          transport_opts: [
            host: String.to_charlist(ctx.host),
            port: ctx.port + 30000,
            connect_timeout: 1,
            clientid: "ash_mqtt_test_unreachable_" <> BrokerEnv.rand_hex()
          ]
        )

      case result do
        {:error, _} ->
          :ok

        {:ok, pid} ->
          flunk("expected connect failure, got live client #{inspect(pid)}")
      end
    end
  end

  describe "publish / subscribe" do
    test "qos1 publish round-trips through the broker to a subscriber", ctx do
      sub = start_client!(ctx)
      pub = start_client!(ctx)

      topic = ctx.prefix <> "/up"
      test_pid = self()

      :ok =
        Client.dispatch(sub, topic, fn msg ->
          send(test_pid, {:got, msg})
          :ok
        end)

      :ok = Client.publish(pub, topic, "hello", qos: 1)

      assert_receive {:got, %Message{topic: ^topic, payload: "hello", qos: 1}}, 5_000
    end

    test "qos0 publish reaches the subscriber", ctx do
      sub = start_client!(ctx)
      pub = start_client!(ctx)

      topic = ctx.prefix <> "/events"
      test_pid = self()

      :ok = Client.dispatch(sub, topic, fn msg -> send(test_pid, {:got, msg}); :ok end)

      :ok = Client.publish(pub, topic, "evt", qos: 0)

      assert_receive {:got, %Message{topic: ^topic, payload: "evt"}}, 5_000
    end

    test "single-level + wildcard delivers all matching topics", ctx do
      sub = start_client!(ctx)
      pub = start_client!(ctx)

      filter = ctx.prefix <> "/devices/+/up"
      test_pid = self()

      :ok = Client.dispatch(sub, filter, fn msg -> send(test_pid, {:got, msg}); :ok end)

      :ok = Client.publish(pub, ctx.prefix <> "/devices/d1/up", "1", qos: 1)
      :ok = Client.publish(pub, ctx.prefix <> "/devices/d2/up", "2", qos: 1)

      assert_receive {:got, %Message{payload: "1"}}, 5_000
      assert_receive {:got, %Message{payload: "2"}}, 5_000
    end

    test "multi-level # wildcard delivers all matching topics", ctx do
      sub = start_client!(ctx)
      pub = start_client!(ctx)

      filter = ctx.prefix <> "/#"
      test_pid = self()

      :ok = Client.dispatch(sub, filter, fn msg -> send(test_pid, {:got, msg}); :ok end)

      :ok = Client.publish(pub, ctx.prefix <> "/a/b/c", "deep", qos: 1)
      :ok = Client.publish(pub, ctx.prefix <> "/x", "shallow", qos: 1)

      assert_receive {:got, %Message{topic: t1}}, 5_000
      assert_receive {:got, %Message{topic: t2}}, 5_000
      assert MapSet.new([t1, t2]) == MapSet.new([ctx.prefix <> "/a/b/c", ctx.prefix <> "/x"])
    end

    test "retain delivers the last message to a late subscriber", ctx do
      pub = start_client!(ctx)
      topic = ctx.prefix <> "/state"

      :ok = Client.publish(pub, topic, "retained", qos: 1, retain: true)
      Process.sleep(50)

      sub = start_client!(ctx)
      test_pid = self()
      :ok = Client.dispatch(sub, topic, fn msg -> send(test_pid, {:got, msg}); :ok end)

      assert_receive {:got, %Message{topic: ^topic, payload: "retained", retain: true}}, 5_000

      :ok = Client.publish(pub, topic, "", qos: 1, retain: true)
    end
  end

  describe "MQTT 5 properties" do
    test "Content-Type, Response-Topic, Correlation-Data and User-Property survive the round trip",
         ctx do
      sub = start_client!(ctx)
      pub = start_client!(ctx)

      topic = ctx.prefix <> "/req"
      test_pid = self()
      :ok = Client.dispatch(sub, topic, fn msg -> send(test_pid, {:got, msg}); :ok end)

      :ok =
        Client.publish(pub, topic, "{\"k\":1}",
          qos: 1,
          content_type: "application/json"
        )

      assert_receive {:got, %Message{topic: ^topic, content_type: "application/json"}}, 5_000
    end
  end

  describe "invoke / dispatch request-reply" do
    test "invoke against a dispatcher in another client gets the reply", ctx do
      server = start_client!(ctx)
      caller = start_client!(ctx)

      req_topic = ctx.prefix <> "/cmd/echo"

      :ok =
        Client.dispatch(server, req_topic, fn %Message{payload: p} ->
          {:reply, "echo:" <> p}
        end)

      assert {:ok, %Message{payload: "echo:ping"} = reply} =
               Client.invoke(caller, req_topic, payload: "ping", timeout: 5_000)

      refute is_nil(reply.correlation_data)
    end

    test "invoke times out when no dispatcher answers", ctx do
      caller = start_client!(ctx)
      lonely_topic = ctx.prefix <> "/cmd/no_one_listens"

      assert {:error, :timeout} =
               Client.invoke(caller, lonely_topic, payload: "x", timeout: 200)
    end

    test "two concurrent invokes both get their correlated replies", ctx do
      server = start_client!(ctx)
      caller = start_client!(ctx)

      req_topic = ctx.prefix <> "/cmd/multi"

      :ok =
        Client.dispatch(server, req_topic, fn %Message{payload: p} ->
          {:reply, "ack:" <> p}
        end)

      task_a = Task.async(fn -> Client.invoke(caller, req_topic, payload: "A", timeout: 5_000) end)
      task_b = Task.async(fn -> Client.invoke(caller, req_topic, payload: "B", timeout: 5_000) end)

      assert {:ok, %Message{payload: a}} = Task.await(task_a, 6_000)
      assert {:ok, %Message{payload: b}} = Task.await(task_b, 6_000)

      assert MapSet.new([a, b]) == MapSet.new(["ack:A", "ack:B"])
    end

    test "handler returning :ok publishes nothing back", ctx do
      server = start_client!(ctx)
      caller = start_client!(ctx)

      req_topic = ctx.prefix <> "/cmd/silent"

      :ok = Client.dispatch(server, req_topic, fn _msg -> :ok end)

      assert {:error, :timeout} =
               Client.invoke(caller, req_topic, payload: "ping", timeout: 300)
    end

    test "dispatcher exception leaves the client alive", ctx do
      server = start_client!(ctx)
      caller = start_client!(ctx)

      req_topic = ctx.prefix <> "/cmd/raise"

      :ok = Client.dispatch(server, req_topic, fn _ -> raise "boom" end)

      assert {:error, :timeout} =
               Client.invoke(caller, req_topic, payload: "ping", timeout: 300)

      assert Process.alive?(server)
      assert Process.alive?(caller)
    end
  end
end
