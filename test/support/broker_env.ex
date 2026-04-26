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
  Block until the broker accepts TCP connections. Raises with a hint to
  start the docker-compose stack if it does not come up in time.
  """
  @spec await_broker!(String.t(), pos_integer(), pos_integer()) :: :ok
  def await_broker!(host, port, deadline_ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    do_wait(String.to_charlist(host), port, deadline)
  end

  defp do_wait(host, port, deadline) do
    case :gen_tcp.connect(host, port, [:binary, active: false], 500) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        :ok

      {:error, _} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise """
          MQTT broker not reachable at #{host}:#{port} after waiting for it to come up.

          Start the local stack with:

              docker compose -f docker/docker-compose.yml up -d

          and re-run with `mix test --only integration` (or set MQTT_BROKER
          to select emqx/mosquitto).
          """
        else
          Process.sleep(200)
          do_wait(host, port, deadline)
        end
    end
  end

  @doc "Random hex string for unique clientids / topic prefixes per test."
  @spec rand_hex(pos_integer()) :: String.t()
  def rand_hex(bytes \\ 6),
    do: Base.encode16(:crypto.strong_rand_bytes(bytes), case: :lower)
end
