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

## Out of scope (v0.1)

* **Runtime MQTT client.** The `action` DSL captures the request/response
  declaration but no client is wired up here; runtime invocation will
  land in a follow-up that picks an MQTT 5 client.
* Topic alias optimisation, custom QoS upgrade/downgrade flows, sticky
  session management beyond MQTT 5 defaults.
* Live EMQX dashboard push (the renderer's output is REST-shaped, but
  the HTTP client lives in operator code).

## Tests

```sh
mix test
```

47 tests + 4 doctests across topic helpers, DSL parse + Info,
broker-config dispatch, Mosquitto ACL rendering (incl. all four ACL
policies), EMQX JSON rendering (incl. `to_json/2` round-trip and `:opaque`
skip), shadow-DSL expansion + direction conventions, and both mix tasks
end-to-end.
