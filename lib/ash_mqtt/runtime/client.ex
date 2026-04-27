defmodule AshMqtt.Runtime.Client do
  @moduledoc """
  GenServer that owns an MQTT transport, tracks pending request/reply
  correlations, and routes incoming messages to dispatcher handlers.

  ## Use

      {:ok, client} =
        AshMqtt.Runtime.Client.start_link(
          transport: AshMqtt.Runtime.Transport.EMQTT,
          transport_opts: [host: ~c"broker.example.com", ...]
        )

      # Fire-and-forget publish
      :ok = AshMqtt.Runtime.Client.publish(client, "tenants/acme/devices/d1/cmd", payload)

      # Request/response over MQTT 5 correlation
      {:ok, reply} =
        AshMqtt.Runtime.Client.invoke(client, "tenants/acme/devices/d1/cmd/read_config",
          payload: <<>>,
          timeout: 5_000)

      # Server-side dispatcher
      :ok =
        AshMqtt.Runtime.Client.dispatch(client, "tenants/+/devices/+/cmd/reboot",
          fn msg -> handle_reboot(msg) end)

  ## Reply correlation

  `invoke/3` allocates a fresh correlation id (16 random bytes), generates
  a unique response topic (`<reply_prefix>/<correlation_hex>`), subscribes
  to that response topic before publishing, and waits for either the
  matching reply or the timeout.

  Replies arriving for a known correlation id are routed back to the
  caller. Replies arriving after timeout are silently dropped.

  ## Dispatcher handlers

  Handlers are functions of one argument (the incoming
  `AshMqtt.Runtime.Message`). The handler may return:

    * `:ok` / `nil` — no reply.
    * `{:reply, body}` — publish `body` to the request's
      `response_topic` with the same correlation_data.
    * `{:reply, body, opts}` — same, with `:qos` / `:content_type`
      forwarded to the publish.

  If the request had no `response_topic`, replies are dropped with a
  log warning.
  """

  use GenServer
  require Logger

  alias AshMqtt.Runtime.Message

  defmodule State do
    @moduledoc false
    defstruct [
      :transport_mod,
      :transport,
      :reply_prefix,
      pending: %{},
      handlers: %{}
    ]
  end

  @type t :: GenServer.server()

  # ─── client API ───────────────────────────────────────────────────────

  @doc """
  Start a client.

  Required:
    * `:transport` — module implementing `AshMqtt.Runtime.Transport`.
    * `:transport_opts` — keyword forwarded to the transport's
      `connect/2`.

  Optional:
    * `:reply_prefix` — base used to derive per-request reply topics.
      Default `"_replies/<self-pid-hex>"`.
    * `:name` — GenServer name registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @doc "Publish a message; fire and forget."
  @spec publish(t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def publish(server, topic, payload, opts \\ []) do
    GenServer.call(server, {:publish, Message.new(topic, payload, opts)})
  end

  @doc """
  Publish a message and wait for a reply correlated by MQTT 5
  correlation-data.

  Options:
    * `:payload` — request payload (default `<<>>`).
    * `:timeout` — milliseconds to wait (default 5_000).
    * `:qos` / `:content_type` — forwarded to the publish.

  Returns `{:ok, %Message{}}` (the reply) or `{:error, :timeout}`.
  """
  @spec invoke(t(), String.t(), keyword()) :: {:ok, Message.t()} | {:error, term()}
  def invoke(server, topic, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(server, {:invoke, topic, opts}, timeout + 500)
  end

  @doc "Subscribe to a topic filter and route incoming messages to `handler`."
  @spec dispatch(t(), String.t(), (Message.t() -> any())) :: :ok | {:error, term()}
  def dispatch(server, topic_filter, handler) when is_function(handler, 1) do
    GenServer.call(server, {:dispatch, topic_filter, handler})
  end

  @doc "Stop the client and disconnect the transport."
  @spec stop(t()) :: :ok
  def stop(server), do: GenServer.stop(server)

  # ─── GenServer ────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    reply_prefix =
      Keyword.get(opts, :reply_prefix, "_replies/" <> hex_pid(self()))

    case transport_mod.connect(transport_opts, self()) do
      {:ok, transport} ->
        {:ok,
         %State{
           transport_mod: transport_mod,
           transport: transport,
           reply_prefix: reply_prefix
         }}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def handle_call({:publish, %Message{} = msg}, _from, state) do
    {:reply, state.transport_mod.publish(state.transport, msg), state}
  end

  def handle_call({:invoke, topic, opts}, from, state) do
    correlation = :crypto.strong_rand_bytes(16)
    correlation_hex = Base.encode16(correlation, case: :lower)
    response_topic = state.reply_prefix <> "/" <> correlation_hex

    timeout = Keyword.get(opts, :timeout, 5_000)
    timer = Process.send_after(self(), {:invoke_timeout, correlation_hex}, timeout)

    pending =
      Map.put(state.pending, correlation_hex, %{from: from, timer: timer, topic: response_topic})

    state = %{state | pending: pending}

    with :ok <- state.transport_mod.subscribe(state.transport, response_topic, 1),
         msg <-
           Message.new(
             topic,
             Keyword.get(opts, :payload, <<>>),
             qos: Keyword.get(opts, :qos, 1),
             content_type: Keyword.get(opts, :content_type),
             response_topic: response_topic,
             correlation_data: correlation
           ),
         :ok <- state.transport_mod.publish(state.transport, msg) do
      {:noreply, state}
    else
      {:error, reason} ->
        Process.cancel_timer(timer)
        {:reply, {:error, reason}, %{state | pending: Map.delete(state.pending, correlation_hex)}}
    end
  end

  def handle_call({:dispatch, topic_filter, handler}, _from, state) do
    case state.transport_mod.subscribe(state.transport, topic_filter, 1) do
      :ok ->
        handlers = Map.put(state.handlers, topic_filter, handler)
        {:reply, :ok, %{state | handlers: handlers}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_info({:ash_mqtt_msg, %Message{} = msg}, state) do
    state =
      if match_pending?(msg, state) do
        route_reply(msg, state)
      else
        route_to_handler(msg, state)
      end

    {:noreply, state}
  end

  def handle_info({:invoke_timeout, correlation_hex}, state) do
    case Map.pop(state.pending, correlation_hex) do
      {%{from: from, topic: topic}, pending} ->
        GenServer.reply(from, {:error, :timeout})
        _ = state.transport_mod.unsubscribe(state.transport, topic)
        {:noreply, %{state | pending: pending}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info({:ash_mqtt_disconnect, reason}, state) do
    Logger.warning("ash_mqtt transport disconnected: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    state.transport_mod.disconnect(state.transport)
    :ok
  end

  # ─── routing ──────────────────────────────────────────────────────────

  defp match_pending?(%Message{correlation_data: nil}, _state), do: false

  defp match_pending?(%Message{correlation_data: c}, state),
    do: Map.has_key?(state.pending, Base.encode16(c, case: :lower))

  defp route_reply(%Message{correlation_data: c} = msg, state) do
    key = Base.encode16(c, case: :lower)

    case Map.pop(state.pending, key) do
      {%{from: from, timer: timer, topic: topic}, pending} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, {:ok, msg})
        _ = state.transport_mod.unsubscribe(state.transport, topic)
        %{state | pending: pending}

      {nil, _} ->
        state
    end
  end

  defp route_to_handler(%Message{topic: topic} = msg, state) do
    case Enum.find(state.handlers, fn {filter, _} -> topic_matches?(filter, topic) end) do
      {_filter, handler} ->
        case safe_call(handler, msg) do
          {:reply, body} -> publish_reply(msg, body, [], state)
          {:reply, body, opts} -> publish_reply(msg, body, opts, state)
          _ -> :ok
        end

        state

      nil ->
        Logger.debug("ash_mqtt unrouted message on #{topic}")
        state
    end
  end

  defp publish_reply(%Message{response_topic: nil} = _req, _body, _opts, _state) do
    Logger.warning("ash_mqtt handler returned :reply but request had no response_topic")
    :ok
  end

  defp publish_reply(%Message{response_topic: topic, correlation_data: c}, body, opts, state) do
    msg =
      Message.new(topic, body,
        qos: Keyword.get(opts, :qos, 1),
        content_type: Keyword.get(opts, :content_type),
        correlation_data: c
      )

    state.transport_mod.publish(state.transport, msg)
  end

  defp safe_call(handler, msg) do
    handler.(msg)
  rescue
    error ->
      Logger.error("ash_mqtt handler raised: #{inspect(error)}")
      :error
  end

  # MQTT topic filter wildcard match: `+` matches one segment, `#`
  # matches the rest.
  @doc false
  def topic_matches?(filter, topic) do
    do_match(String.split(filter, "/"), String.split(topic, "/"))
  end

  defp do_match([], []), do: true
  defp do_match(["#" | _], _rest), do: true
  defp do_match(["+" | f_rest], [_ | t_rest]), do: do_match(f_rest, t_rest)
  defp do_match([same | f_rest], [same | t_rest]), do: do_match(f_rest, t_rest)
  defp do_match(_, _), do: false

  defp hex_pid(pid) do
    pid
    |> :erlang.pid_to_list()
    |> List.to_string()
    |> :erlang.phash2()
    |> Integer.to_string(16)
    |> String.downcase()
  end
end
