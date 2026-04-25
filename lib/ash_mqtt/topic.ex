defmodule AshMqtt.Topic do
  @moduledoc """
  Helpers for working with topic patterns expressed in the
  `:placeholder` style this library uses.

      iex> AshMqtt.Topic.variables("tenants/:tenant_id/devices/:device_id/up")
      [:tenant_id, :device_id]

      iex> AshMqtt.Topic.render("tenants/:tenant_id/devices/:device_id/up", :mosquitto)
      "tenants/%u/devices/%c/up"

      iex> AshMqtt.Topic.render("tenants/:tenant_id/devices/:device_id/up", :emqx)
      "tenants/${username}/devices/${clientid}/up"

      iex> AshMqtt.Topic.match_filter("tenants/:tenant_id/+/up", :mosquitto)
      "tenants/+/+/up"
  """

  @doc "List the placeholder atoms in a pattern, in left-to-right order."
  @spec variables(AshMqtt.pattern()) :: [atom()]
  def variables(pattern) when is_binary(pattern) do
    pattern
    |> String.split("/")
    |> Enum.flat_map(fn
      ":" <> rest -> [String.to_atom(rest)]
      _ -> []
    end)
  end

  @doc """
  Render a pattern in the conventions of the named broker.

  Mosquitto:
    * `:tenant_id`  → `%u` (the connected user / cert CN)
    * `:device_id`  → `%c` (the client id)
    * other names   → broker single-level wildcard `+`

  EMQX:
    * `:tenant_id`  → `${username}`
    * `:device_id`  → `${clientid}`
    * other names   → `+`
  """
  @spec render(AshMqtt.pattern(), :mosquitto | :emqx) :: String.t()
  def render(pattern, :mosquitto), do: substitute(pattern, &mosquitto_var/1)
  def render(pattern, :emqx), do: substitute(pattern, &emqx_var/1)

  @doc "Render a pattern as a wildcard match filter (every variable becomes `+`)."
  @spec match_filter(AshMqtt.pattern(), :mosquitto | :emqx) :: String.t()
  def match_filter(pattern, _broker), do: substitute(pattern, fn _ -> "+" end)

  defp substitute(pattern, mapper) do
    pattern
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> name -> mapper.(String.to_atom(name))
      segment -> segment
    end)
  end

  defp mosquitto_var(:tenant_id), do: "%u"
  defp mosquitto_var(:device_id), do: "%c"
  defp mosquitto_var(_), do: "+"

  defp emqx_var(:tenant_id), do: "${username}"
  defp emqx_var(:device_id), do: "${clientid}"
  defp emqx_var(_), do: "+"
end
