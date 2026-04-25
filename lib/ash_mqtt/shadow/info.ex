defmodule AshMqtt.Shadow.Info do
  @moduledoc """
  Introspection helpers for the `mqtt_shadow do … end` section.

      AshMqtt.Shadow.Info.declared?(MyApp.Device.Shadow)
      AshMqtt.Shadow.Info.topics(MyApp.Device.Shadow)

  `topics/1` returns four `AshMqtt.Resource.Topic` structs (with
  pattern, qos, retain, payload_format, acl, and the conventional
  direction for each suffix) — the same struct shape produced by the
  `mqtt do …` DSL, so the same broker-config renderers can consume both
  surfaces uniformly.
  """

  use Spark.InfoGenerator,
    extension: AshMqtt.Shadow,
    sections: [:mqtt_shadow]

  alias AshMqtt.Resource.Topic

  @suffix_directions %{
    "desired" => :inbound,
    "reported" => :outbound,
    "delta" => :inbound,
    "get" => :inbound
  }

  @doc "Whether the resource declared an `mqtt_shadow` section at all."
  @spec declared?(module()) :: boolean()
  def declared?(resource) do
    case mqtt_shadow_base(resource) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Expand the shadow declaration into four `AshMqtt.Resource.Topic`
  structs, one per suffix.
  """
  @spec topics(module()) :: [Topic.t()]
  def topics(resource) do
    if declared?(resource) do
      base = mqtt_shadow_base!(resource)
      qos = mqtt_shadow_qos!(resource)
      retain = mqtt_shadow_retain!(resource)
      fmt = mqtt_shadow_payload_format!(resource)
      acl = mqtt_shadow_acl!(resource)
      as = safe_get(:as, resource)

      for {suffix, direction} <- @suffix_directions do
        %Topic{
          pattern: base <> "/" <> suffix,
          as: shadow_as(as, suffix),
          direction: direction,
          qos: qos,
          retain: retain,
          payload_format: fmt,
          acl: acl
        }
      end
    else
      []
    end
  end

  @doc """
  Convenience: combined topics from the `mqtt` and `mqtt_shadow`
  sections, deduped by pattern.
  """
  @spec all_topics(module()) :: [Topic.t()]
  def all_topics(resource) do
    base_topics =
      if function_exported?(AshMqtt.Resource.Info, :topics, 1) do
        try do
          AshMqtt.Resource.Info.topics(resource)
        rescue
          _ -> []
        end
      else
        []
      end

    Enum.uniq_by(base_topics ++ topics(resource), & &1.pattern)
  end

  defp shadow_as(nil, suffix), do: String.to_atom("shadow_" <> suffix)

  defp shadow_as(as, suffix) when is_atom(as),
    do: String.to_atom(Atom.to_string(as) <> "_" <> suffix)

  defp safe_get(option, resource) do
    case apply(__MODULE__, :"mqtt_shadow_#{option}", [resource]) do
      {:ok, value} -> value
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
