defmodule AshMqtt.BrokerConfig.EMQX do
  @moduledoc """
  Render an MQTT-enabled set of resources to EMQX REST-API-shaped JSON.

  Two artifacts are emitted, each as a JSON-encodable map (or list of
  maps). Operators feed them to `POST /api/v5/authorization/sources` and
  `POST /api/v5/rules` respectively, or write them to disk and import via
  the EMQX dashboard's bulk import.

  ## ACL rules (`acl/0`)

  Each topic emits one EMQX authorization rule, keyed by username
  (`${username}` = the cert CN convention). `direction:` controls
  `action: subscribe | publish | all`. ACL kind:

    * `:tenant_isolated` — `${username}` and `${clientid}` substituted in
      the topic; permission `:allow`.
    * `:device_owned` — same but with a comment hint that operators
      should also enforce `clientid_must_match_username` at the listener.
    * `:public_subscribe`, `:public_publish` — split into two rules so
      the public side and the tenant side can be expressed independently.

  ## Validation rules (`rules/0`)

  EMQX's rule engine can attach payload validation hooks. We emit one
  rule per topic with a non-`:opaque` payload format; the rule's body is
  a SQL-shaped string `SELECT * FROM "<topic>" WHERE …` that schema
  registries hook into. The exact registry binding is operator-specific;
  the rule shape is what's stable.
  """

  alias AshMqtt.BrokerConfig
  alias AshMqtt.Resource.{Action, Info, Topic}

  @doc "Combined config bundle: %{acl: [...], rules: [...]}."
  @spec render([module()], keyword()) :: %{acl: list(map()), rules: list(map())}
  def render(resources, opts \\ []) when is_list(resources) do
    %{
      acl: Enum.flat_map(resources, &resource_acl/1) ++ Keyword.get(opts, :extra_acl, []),
      rules: Enum.flat_map(resources, &resource_rules/1) ++ Keyword.get(opts, :extra_rules, [])
    }
  end

  @doc "Pretty-printed JSON of the bundle, ready to write to disk."
  @spec to_json([module()], keyword()) :: String.t()
  def to_json(resources, opts \\ []) do
    resources
    |> render(opts)
    |> Jason.encode!(pretty: true)
  end

  defp resource_acl(resource) do
    topics_acl = Enum.flat_map(BrokerConfig.topics(resource), &topic_acl(resource, &1))
    actions_acl = Enum.flat_map(BrokerConfig.actions(resource), &action_acl(resource, &1))
    topics_acl ++ actions_acl
  end

  defp resource_rules(resource) do
    Enum.flat_map(BrokerConfig.topics(resource), &topic_rule(resource, &1)) ++
      Enum.flat_map(BrokerConfig.actions(resource), &action_rule(resource, &1))
  end

  # ─── ACL ────────────────────────────────────────────────────────────────

  defp topic_acl(resource, %Topic{} = topic) do
    filter = AshMqtt.Topic.render(topic.pattern, :emqx)
    acl = Info.effective_acl(resource, topic)
    action_kind = direction_to_action(topic.direction)

    rules_for_acl(acl, filter, action_kind, resource)
  end

  defp action_acl(resource, %Action{topic: pattern, reply: reply?}) do
    filter = AshMqtt.Topic.render(pattern, :emqx)
    acl = Info.mqtt_acl!(resource)

    base = rules_for_acl(acl, filter, :all, resource)

    if reply? do
      base ++ rules_for_acl(acl, filter <> "/reply/+", :all, resource)
    else
      base
    end
  end

  defp rules_for_acl(:tenant_isolated, filter, action_kind, resource) do
    [
      %{
        permission: "allow",
        action: action_atom_to_string(action_kind),
        topic: filter,
        username: "${username}",
        comment: "tenant_isolated for #{inspect(resource)}"
      }
    ]
  end

  defp rules_for_acl(:device_owned, filter, action_kind, resource) do
    [
      %{
        permission: "allow",
        action: action_atom_to_string(action_kind),
        topic: filter,
        clientid: "${clientid}",
        comment:
          "device_owned for #{inspect(resource)} — pair with listener-level clientid_must_match_username"
      }
    ]
  end

  defp rules_for_acl(:public_subscribe, filter, _action_kind, resource) do
    [
      %{
        permission: "allow",
        action: "subscribe",
        topic: filter,
        username: "all",
        comment: "public_subscribe (anyone) for #{inspect(resource)}"
      },
      %{
        permission: "allow",
        action: "publish",
        topic: filter,
        username: "${username}",
        comment: "public_subscribe (only tenant publishes) for #{inspect(resource)}"
      }
    ]
  end

  defp rules_for_acl(:public_publish, filter, _action_kind, resource) do
    [
      %{
        permission: "allow",
        action: "publish",
        topic: filter,
        username: "all",
        comment: "public_publish (anyone) for #{inspect(resource)}"
      },
      %{
        permission: "allow",
        action: "subscribe",
        topic: filter,
        username: "${username}",
        comment: "public_publish (only tenant subscribes) for #{inspect(resource)}"
      }
    ]
  end

  defp direction_to_action(:inbound), do: :subscribe
  defp direction_to_action(:outbound), do: :publish
  defp direction_to_action(:bidirectional), do: :all
  defp direction_to_action(nil), do: :all

  defp action_atom_to_string(:subscribe), do: "subscribe"
  defp action_atom_to_string(:publish), do: "publish"
  defp action_atom_to_string(:all), do: "all"

  # ─── Rules (validation hooks) ──────────────────────────────────────────

  defp topic_rule(resource, %Topic{} = topic) do
    case Info.effective_payload_format(resource, topic) do
      :opaque ->
        []

      :arrow_ipc ->
        # Arrow IPC validation isn't a broker concern — it's checked at
        # the ingest endpoint. Skip the rule.
        []

      fmt ->
        [validation_rule(resource, AshMqtt.Topic.render(topic.pattern, :emqx), fmt, topic.as)]
    end
  end

  defp action_rule(resource, %Action{} = action) do
    fmt = Info.effective_payload_format(resource, action)

    case fmt do
      :opaque -> []
      :arrow_ipc -> []
      _ -> [validation_rule(resource, AshMqtt.Topic.render(action.topic, :emqx), fmt, action.name)]
    end
  end

  defp validation_rule(resource, filter, payload_format, name) do
    %{
      name: rule_name(resource, name),
      enable: true,
      sql: ~s(SELECT * FROM "#{filter}"),
      description:
        "Schema-validate #{payload_format} payloads on #{filter} for #{inspect(resource)}",
      metadata: %{
        payload_format: Atom.to_string(payload_format),
        resource: inspect(resource),
        topic: filter
      }
    }
  end

  defp rule_name(resource, name) when is_atom(name) do
    suffix = if is_nil(name), do: "topic", else: Atom.to_string(name)
    inspect(resource) <> "." <> suffix
  end

  defp rule_name(resource, _), do: inspect(resource) <> ".topic"
end
