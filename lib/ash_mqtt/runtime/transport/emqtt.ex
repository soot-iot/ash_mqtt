defmodule AshMqtt.Runtime.Transport.EMQTT do
  @moduledoc """
  Production transport over the `:emqtt` Erlang client.

  Pulled in only when the operator added `{:emqtt, "~> 1.14"}` to their
  app's deps (`:emqtt` is an `optional: true` dep of `ash_mqtt`).
  Compile-time `Code.ensure_loaded?/1` guards keep the rest of
  `ash_mqtt` usable without it.

  ## Connection options

      AshMqtt.Runtime.Transport.EMQTT.connect([
        host: ~c"broker.example.com",
        port: 8883,
        proto_ver: :v5,
        ssl: true,
        ssl_opts: [
          certfile: "priv/pki/client_chain.pem",
          keyfile: "priv/pki/client_key.pem",
          cacertfile: "priv/pki/trust_bundle.pem",
          verify: :verify_peer
        ]
      ], self())

  Every option is forwarded to `:emqtt.start_link/1`. The runtime adds
  `msg_handler` for inbound delivery to the owning process.
  """

  @behaviour AshMqtt.Runtime.Transport

  alias AshMqtt.Runtime.Message

  defstruct [:pid]

  @type t :: %__MODULE__{pid: pid()}

  @impl true
  def connect(opts, owner) when is_pid(owner) do
    if Code.ensure_loaded?(:emqtt) do
      do_connect(opts, owner)
    else
      {:error, :emqtt_not_available}
    end
  end

  defp do_connect(opts, owner) do
    handler = %{
      publish: fn props -> send(owner, {:ash_mqtt_msg, from_emqtt(props)}) end,
      disconnected: fn reason -> send(owner, {:ash_mqtt_disconnect, reason}) end
    }

    opts =
      opts
      |> Keyword.put_new(:proto_ver, :v5)
      |> Keyword.put(:msg_handler, handler)

    with {:ok, pid} <- :emqtt.start_link(opts),
         {:ok, _} <- :emqtt.connect(pid) do
      {:ok, %__MODULE__{pid: pid}}
    end
  end

  @impl true
  def publish(%__MODULE__{pid: pid}, %Message{} = msg) do
    props = build_props(msg)
    qos = msg.qos || 0
    retain = msg.retain || false

    :emqtt.publish(pid, msg.topic, props, msg.payload, [{:qos, qos}, {:retain, retain}])
    |> normalise()
  end

  @impl true
  def subscribe(%__MODULE__{pid: pid}, filter, qos) do
    case :emqtt.subscribe(pid, %{}, [{filter, [{:qos, qos}]}]) do
      {:ok, _props, _reasons} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def unsubscribe(%__MODULE__{pid: pid}, filter) do
    case :emqtt.unsubscribe(pid, %{}, [filter]) do
      {:ok, _props, _reasons} -> :ok
      {:error, _} = err -> err
    end
  end

  @impl true
  def disconnect(%__MODULE__{pid: pid}) do
    _ = :emqtt.disconnect(pid)
    :ok
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  defp build_props(%Message{} = msg) do
    %{}
    |> maybe_put(:"Content-Type", msg.content_type)
    |> maybe_put(:"Response-Topic", msg.response_topic)
    |> maybe_put(:"Correlation-Data", msg.correlation_data)
    |> maybe_put(:"User-Property", flatten_user_props(msg.user_properties))
  end

  defp maybe_put(map, _, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp flatten_user_props(nil), do: nil
  defp flatten_user_props(map) when is_map(map), do: Enum.to_list(map)

  defp from_emqtt(%{topic: topic, payload: payload} = msg) do
    properties = Map.get(msg, :properties, %{})

    %Message{
      topic: to_string(topic),
      payload: payload,
      qos: Map.get(msg, :qos),
      retain: Map.get(msg, :retain),
      content_type: nil_or_string(Map.get(properties, :"Content-Type")),
      response_topic: nil_or_string(Map.get(properties, :"Response-Topic")),
      correlation_data: Map.get(properties, :"Correlation-Data"),
      user_properties: Map.new(Map.get(properties, :"User-Property", []))
    }
  end

  defp normalise(:ok), do: :ok
  defp normalise({:ok, _}), do: :ok
  defp normalise({:error, _} = err), do: err

  defp nil_or_string(nil), do: nil
  defp nil_or_string(bin) when is_binary(bin), do: bin
  defp nil_or_string(other), do: to_string(other)
end
