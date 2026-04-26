# `ash_mqtt`

MQTT as an Ash transport. Two cooperating extensions:

* **`AshMqtt.Resource`** — adds an `mqtt do … end` section to a resource
  for declaring topic patterns, QoS, retain, payload format, ACL policy,
  and Ash actions exposed at MQTT topics (request/response with MQTT 5
  correlation).
* **`AshMqtt.Shadow`** — adds an `mqtt_shadow do … end` section that
  expands a base pattern into the four conventional shadow topics
  (`desired`, `reported`, `delta`, `get`) following the AWS / Azure
  shape so existing tooling and devices interop.

Topic declarations compile to broker-native configuration:

* `AshMqtt.BrokerConfig.Mosquitto.render/2` — Mosquitto ACL file.
* `AshMqtt.BrokerConfig.EMQX.render/2` (and `to_json/2`) — EMQX REST API
  bundle (`%{acl: [...], rules: [...]}`).

Both renderers go through `AshMqtt.BrokerConfig`, which combines
declarations from both DSLs so a resource using either or both is
rendered the same way.

## DSL surface

```elixir
defmodule MyApp.Device do
  use Ash.Resource, extensions: [AshMqtt.Resource]

  mqtt do
    qos 1
    retain false
    payload_format :json
    acl :tenant_isolated

    topic "tenants/:tenant_id/devices/:device_id/cmd",
      as: :cmd_in,
      direction: :inbound

    topic "tenants/:tenant_id/devices/:device_id/up",
      as: :events_out,
      direction: :outbound,
      qos: 0

    action :reboot,
      topic: "tenants/:tenant_id/devices/:device_id/cmd/reboot"

    action :read_config,
      topic: "tenants/:tenant_id/devices/:device_id/cmd/read_config",
      reply: true,
      timeout: 5_000
  end
end

defmodule MyApp.Device.Shadow do
  use Ash.Resource, extensions: [AshMqtt.Shadow]

  mqtt_shadow do
    base "tenants/:tenant_id/devices/:device_id/shadow"
    as :device_shadow
    qos 1
    retain true
    payload_format :json
    acl :tenant_isolated

    desired_attributes [:led, :sample_rate, :firmware_version]
    reported_attributes [:led, :sample_rate, :firmware_version, :uptime_s]
  end
end
```

`:variable` placeholders in patterns are translated per broker:

| placeholder   | Mosquitto | EMQX            |
|---------------|-----------|-----------------|
| `:tenant_id`  | `%u`      | `${username}`   |
| `:device_id`  | `%c`      | `${clientid}`   |
| anything else | `+`       | `+`             |

## ACL policies

| name                 | meaning                                                           |
|----------------------|-------------------------------------------------------------------|
| `:tenant_isolated`   | per-cert (`%u` / `${username}`); the default                      |
| `:device_owned`      | per-client-id; pair with `clientid_must_match_username` listener  |
| `:public_subscribe`  | anyone subscribes; only the tenant publishes                      |
| `:public_publish`    | anyone publishes; only the tenant subscribes                      |

## Mix tasks

```sh
mix ash_mqtt.gen.mosquitto_acl --out priv/broker/mosquitto.acl \
                               --resource MyApp.Device \
                               --resource MyApp.Device.Shadow

mix ash_mqtt.gen.emqx_config --out priv/broker/emqx.json \
                             --resource MyApp.Device
```

Pushing the EMQX bundle to a live broker (`POST /api/v5/...`) is left to
the operator; the renderers stop at producing the artifacts.

## Runtime

`AshMqtt.Runtime.Client` is a `GenServer` that owns an MQTT
connection, publishes / subscribes, and tracks pending request/reply
correlations. It runs on top of any module implementing the
`AshMqtt.Runtime.Transport` behavior. Two implementations ship:

| transport                              | use                                                      |
|----------------------------------------|----------------------------------------------------------|
| `AshMqtt.Runtime.Transport.EMQTT`      | production; talks to a real broker via the `:emqtt` lib |
| `AshMqtt.Runtime.Transport.Test`       | in-memory; tests record published messages + inject inbound deliveries |

```elixir
{:ok, client} =
  AshMqtt.Runtime.Client.start_link(
    transport: AshMqtt.Runtime.Transport.EMQTT,
    transport_opts: [
      host: ~c"broker.example.com",
      port: 8883,
      ssl: true,
      ssl_opts: [
        certfile: "priv/pki/client_chain.pem",
        keyfile:  "priv/pki/client_key.pem",
        cacertfile: "priv/pki/trust_bundle.pem",
        verify: :verify_peer
      ]
    ]
  )

# Fire-and-forget
:ok = AshMqtt.Runtime.Client.publish(client, "topic/up", "hello")

# Request / reply (MQTT 5 correlation)
{:ok, reply} =
  AshMqtt.Runtime.Client.invoke(client,
    "tenants/acme/devices/d1/cmd/read_config",
    payload: <<>>, timeout: 5_000)

# Server-side dispatcher: the handler may return :ok / {:reply, body} /
# {:reply, body, opts}. {:reply, _} publishes the body to the request's
# response_topic with the same correlation_data.
:ok =
  AshMqtt.Runtime.Client.dispatch(client,
    "tenants/+/devices/+/cmd/reboot",
    fn msg -> handle_reboot(msg) end)
```

`:emqtt` is an `optional: true` dependency — operators who only use
the DSL + broker-config generators don't pull it (and its
`:quicer` C-NIF) into their build.

## Out of scope (v0.1)

* Topic alias optimisation, custom QoS upgrade/downgrade flows, sticky
  session management beyond MQTT 5 defaults.
* Reconnect / backoff policy in the runtime client. Operators wrap the
  GenServer in a `Supervisor` for restart; smarter retry comes later.
* Live EMQX dashboard push (the renderer's output is REST-shaped, but
  the HTTP client lives in operator code).

## Tests

```sh
mix test
```

60 tests + 4 doctests across topic helpers, DSL parse + Info,
broker-config dispatch, Mosquitto ACL rendering (incl. all four ACL
policies), EMQX JSON rendering (incl. `to_json/2` round-trip and `:opaque`
skip), shadow-DSL expansion + direction conventions, both mix tasks
end-to-end, and the runtime layer over the in-memory `Test` transport
(publish, invoke happy path with correlation roundtrip + auto-subscribe
to the response topic, invoke timeout, late-reply silent drop, dispatch
to a handler with `{:reply, body}` round trip back to the request's
response_topic, handler returning `:ok` publishes nothing, handler
exception is caught and the client stays alive, MQTT topic-filter
wildcards including `+` and `#`).
