defmodule AshMqtt.Runtime.MessageTest do
  use ExUnit.Case, async: true

  alias AshMqtt.Runtime.Message

  test "new/3 fills sensible defaults" do
    msg = Message.new("topic", "body")

    assert msg.topic == "topic"
    assert msg.payload == "body"
    assert msg.qos == 0
    assert msg.retain == false
    assert is_nil(msg.content_type)
    assert is_nil(msg.response_topic)
    assert is_nil(msg.correlation_data)
  end

  test "new/3 carries every option through" do
    msg =
      Message.new("topic", "body",
        qos: 2,
        retain: true,
        content_type: "application/json",
        response_topic: "replies/x",
        correlation_data: <<1, 2, 3>>,
        user_properties: %{"trace_id" => "abc"}
      )

    assert msg.qos == 2
    assert msg.retain == true
    assert msg.content_type == "application/json"
    assert msg.response_topic == "replies/x"
    assert msg.correlation_data == <<1, 2, 3>>
    assert msg.user_properties == %{"trace_id" => "abc"}
  end
end
