defmodule AshMqtt.Test.BrokerEnv do
  @moduledoc """
  Helpers for the optional integration tests that talk to a real
  broker. Selection between `emqx` and `mosquitto` is controlled by the
  `MQTT_BROKER` env var; ports default to `1883` (emqx) and `1884`
  (mosquitto), matching `docker/docker-compose.yml`.
  """

  @default_host "127.0.0.1"
  @default_emqx_port 1883
  @default_mosquitto_port 1884

  @type endpoint :: %{broker: :emqx | :mosquitto, host: String.t(), port: pos_integer()}

  @spec endpoint() :: endpoint()
  def endpoint do
    broker = broker_name()
    host = System.get_env("MQTT_HOST", @default_host)
    port = port_for(broker)
    %{broker: broker, host: host, port: port}
  end

  @spec broker_name() :: :emqx | :mosquitto
  def broker_name do
    case System.get_env("MQTT_BROKER", "emqx") do
      "emqx" -> :emqx
      "mosquitto" -> :mosquitto
      other -> raise "Unknown MQTT_BROKER #{inspect(other)}; expected \"emqx\" or \"mosquitto\""
    end
  end

  defp port_for(:emqx),
    do: env_int("MQTT_EMQX_PORT", @default_emqx_port)

  defp port_for(:mosquitto),
    do: env_int("MQTT_MOSQUITTO_PORT", @default_mosquitto_port)

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  @doc """
  Block until the broker accepts a full MQTT 5 CONNECT (not just TCP).
  Raises with a hint to start the docker-compose stack if it does not
  come up in time.

  EMQX in particular opens its TCP listener several seconds before it
  is ready to handle MQTT, so a TCP-only probe can race the broker's
  boot sequence and the runtime client then sees `:tcp_closed`.
  """
  @spec await_broker!(String.t(), pos_integer(), pos_integer()) :: :ok
  def await_broker!(host, port, deadline_ms \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    do_wait(host, port, deadline)
  end

  defp do_wait(host, port, deadline) do
    case probe_mqtt(host, port) do
      :ok ->
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise """
          MQTT broker not reachable at #{host}:#{port} after waiting for it to come up.

          Start the local stack with:

              docker compose -f docker/docker-compose.yml up -d

          and re-run with `mix test --only integration` (or set MQTT_BROKER
          to select emqx/mosquitto).
          """
        else
          Process.sleep(250)
          do_wait(host, port, deadline)
        end
    end
  end

  defp probe_mqtt(host, port) do
    Process.flag(:trap_exit, true)

    opts = [
      host: String.to_charlist(host),
      port: port,
      proto_ver: :v5,
      clean_start: true,
      connect_timeout: 2,
      clientid: "ash_mqtt_probe_" <> rand_hex()
    ]

    with {:ok, pid} <- :emqtt.start_link(opts),
         {:ok, _} <- :emqtt.connect(pid) do
      _ = :emqtt.disconnect(pid)
      drain_exits(pid)
      :ok
    else
      {:error, _} = err ->
        drain_exits(:any)
        err
    end
  catch
    :exit, reason ->
      drain_exits(:any)
      {:error, reason}
  end

  defp drain_exits(_pid) do
    receive do
      {:EXIT, _, _} -> drain_exits(:any)
    after
      0 -> :ok
    end
  end

  @doc "Random hex string for unique clientids / topic prefixes per test."
  @spec rand_hex(pos_integer()) :: String.t()
  def rand_hex(bytes \\ 6),
    do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
end
