defmodule AshMqtt.Runtime.ClientTest do
  use ExUnit.Case, async: true

  alias AshMqtt.Runtime.{Client, Message}
  alias AshMqtt.Runtime.Transport.Test, as: TestTransport

  defp start_client!(opts \\ []) do
    {:ok, client} =
      Client.start_link(
        Keyword.merge(
          [transport: TestTransport, transport_opts: [], reply_prefix: "_replies/test"],
          opts
        )
      )

    transport = :sys.get_state(client).transport
    {client, transport}
  end

  describe "publish/4" do
    test "fire-and-forget enqueues a message on the transport" do
      {client, transport} = start_client!()

      assert :ok = Client.publish(client, "topic/up", "hello", qos: 1, retain: true)

      [msg] = TestTransport.published(transport)
      assert msg.topic == "topic/up"
      assert msg.payload == "hello"
      assert msg.qos == 1
      assert msg.retain == true
    end
  end

  describe "invoke/3 happy path" do
    test "subscribes to the response topic and returns the matching reply" do
      {client, transport} = start_client!()

      caller = self()

      task =
        Task.async(fn ->
          Client.invoke(client, "topic/cmd/read_config",
            payload: "req",
            timeout: 1_000
          )
        end)

      # Wait for the publish to land on the transport.
      published =
        Enum.reduce_while(1..50, [], fn _, _ ->
          case TestTransport.published(transport) do
            [] -> Process.sleep(5) && {:cont, []}
            list -> {:halt, list}
          end
        end)

      [request] = published
      assert request.response_topic =~ ~r/^_replies\/test\/[0-9a-f]+$/
      refute is_nil(request.correlation_data)
      assert MapSet.member?(TestTransport.subscriptions(transport), request.response_topic)

      # Simulate the device replying.
      reply_msg = %Message{
        topic: request.response_topic,
        payload: "ok",
        correlation_data: request.correlation_data
      }

      TestTransport.deliver(transport, reply_msg)

      assert {:ok, %Message{payload: "ok"} = reply} = Task.await(task, 2_000)
      assert reply.correlation_data == request.correlation_data

      # Caller no longer subscribed to the response topic.
      assert request.response_topic in TestTransport.unsubscribed(transport)
      _ = caller
    end
  end

  describe "invoke/3 timeout" do
    test "returns {:error, :timeout} when no reply arrives" do
      {client, _transport} = start_client!()

      assert {:error, :timeout} =
               Client.invoke(client, "topic/cmd/read_config", payload: "req", timeout: 50)
    end

    test "drops late replies silently after timeout" do
      {client, transport} = start_client!()

      assert {:error, :timeout} =
               Client.invoke(client, "topic/cmd/read_config", payload: "req", timeout: 30)

      # Late reply should not crash the client.
      [request] = TestTransport.published(transport)

      late = %Message{
        topic: request.response_topic,
        payload: "late",
        correlation_data: request.correlation_data
      }

      TestTransport.deliver(transport, late)

      # Client still alive after the late delivery.
      assert Process.alive?(client)
    end
  end

  describe "dispatch/3 → reply round trip" do
    test "incoming message routes to handler; {:reply, body} publishes back to response_topic" do
      {client, transport} = start_client!()

      :ok =
        Client.dispatch(client, "topic/+/cmd/+", fn msg ->
          assert msg.payload == "ping"
          {:reply, "pong"}
        end)

      assert MapSet.member?(TestTransport.subscriptions(transport), "topic/+/cmd/+")

      incoming = %Message{
        topic: "topic/d1/cmd/echo",
        payload: "ping",
        response_topic: "_replies/upstream/abc",
        correlation_data: <<0xFE, 0xED, 0xFA, 0xCE>>,
        qos: 1
      }

      TestTransport.deliver(transport, incoming)

      # Allow async handler publish to settle.
      Process.sleep(20)

      published = TestTransport.published(transport)
      reply = Enum.find(published, &(&1.topic == "_replies/upstream/abc"))

      refute is_nil(reply)
      assert reply.payload == "pong"
      assert reply.correlation_data == incoming.correlation_data
    end

    test "handler returning :ok publishes nothing" do
      {client, transport} = start_client!()

      :ok = Client.dispatch(client, "topic/up", fn _ -> :ok end)

      TestTransport.deliver(transport, %Message{topic: "topic/up", payload: "x"})
      Process.sleep(20)

      assert TestTransport.published(transport) == []
    end

    test "handler returning {:reply, body} on a request without a response_topic logs and skips" do
      {client, transport} = start_client!()

      :ok = Client.dispatch(client, "topic/up", fn _ -> {:reply, "lonely"} end)

      TestTransport.deliver(transport, %Message{topic: "topic/up", payload: "x"})
      Process.sleep(20)

      assert TestTransport.published(transport) == []
    end

    test "an exception in a handler is caught and the client stays alive" do
      {client, transport} = start_client!()

      :ok = Client.dispatch(client, "topic/up", fn _ -> raise "boom" end)

      TestTransport.deliver(transport, %Message{topic: "topic/up", payload: "x"})
      Process.sleep(20)

      assert Process.alive?(client)
    end
  end

  describe "topic_matches?/2" do
    test "exact match" do
      assert Client.topic_matches?("a/b/c", "a/b/c")
      refute Client.topic_matches?("a/b/c", "a/b/d")
    end

    test "single-level wildcard" do
      assert Client.topic_matches?("a/+/c", "a/b/c")
      assert Client.topic_matches?("tenants/+/devices/+/cmd", "tenants/acme/devices/d1/cmd")
      refute Client.topic_matches?("a/+/c", "a/b/c/d")
    end

    test "multi-level wildcard" do
      assert Client.topic_matches?("a/#", "a/b/c/d")
      assert Client.topic_matches?("#", "anything/at/all")
    end
  end
end
