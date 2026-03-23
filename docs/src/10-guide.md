# Usage Guide

## Working with OCPP Types

OCPP.jl provides typed Julia structs for every OCPP message. Types live in version-specific submodules: `OCPP.V16` (28 actions) and `OCPP.V201` (64 actions).

```@example guide
using OCPP
using OCPP.V16  # brings BootNotificationRequest, HeartbeatRequest, etc. into scope
import JSON     # use import (not using) to avoid conflict with V201's JSON enum member
nothing # hide
```

### Constructing Messages

All message structs use `@kwdef`, so you construct them with keyword arguments. Required fields must be provided; optional fields default to `nothing`.

```@example guide
# V16: required fields are chargePointVendor and chargePointModel
req = BootNotificationRequest(
    charge_point_vendor = "MyVendor",
    charge_point_model = "MyModel",
)
```

```@example guide
# Optional fields default to nothing
req.firmware_version
```

V201 uses nested types that are separate structs:

```@example guide201
using OCPP
import JSON
station = OCPP.V201.ChargingStation(model = "M", vendor_name = "V")
req201 = OCPP.V201.BootNotificationRequest(
    reason = OCPP.V201.BootReasonPowerUp,
    charging_station = station,
)
```

### JSON Serialization

Serialize with `JSON.json` and deserialize with `JSON.parse`. Field names are automatically converted between Julia's `snake_case` and OCPP's `camelCase` on the wire.

```@example guide
json_str = JSON.json(req)
```

```@example guide
req2 = JSON.parse(json_str, BootNotificationRequest)
req == req2
```

!!! note "null vs omitted"
    Optional fields set to `nothing` serialize as `null` in JSON (not omitted). This is valid OCPP and round-trips correctly.

## Enums

OCPP enum values (like `"Accepted"`, `"Rejected"`) are represented as Julia `@enum` types. They serialize to/from their OCPP string values automatically.

```@example guide
resp = BootNotificationResponse(
    status = RegistrationAccepted,
    current_time = "2025-01-01T00:00:00Z",
    interval = 300,
)
JSON.json(resp)
```

### Enum Naming Conventions

Enum members are prefixed to avoid naming conflicts:

- **V16**: Prefixes come from a hand-curated registry in `src/v16/registries.jl`. Example: `RegistrationStatus` enum has members `RegistrationAccepted`, `RegistrationPending`, `RegistrationRejected`.
- **V201**: Prefixes are auto-derived from the definition name. Members shared across multiple enums or that shadow Base names get a prefix. Example: `BootReason` enum has members `BootReasonPowerUp`, `BootReasonApplicationReset`, etc.

```@example guide
# List all members of a V16 enum
instances(RegistrationStatus) |> collect
```

## Action Registry

Each version submodule exports an action registry that maps action names to their request/response types.

```@example guide
V16.request_type("BootNotification")
```

```@example guide
V16.response_type("BootNotification")
```

```@example guide
# Number of actions per version
length(V16.V16_ACTIONS), length(OCPP.V201.V201_ACTIONS)
```

## Wire Format (OCPP-J Codec)

OCPP-J transmits messages as JSON arrays over WebSocket. Use `encode`/`decode` to convert between `OCPPMessage` types and JSON strings.

```@example guide
payload = Dict{String,Any}("chargePointVendor" => "MyVendor", "chargePointModel" => "MyModel")
msg = Call("unique-id-1", "BootNotification", payload)
wire = encode(msg)
```

```@example guide
decoded = decode(wire)
```

```@example guide
decoded.action
```

See [Codec](@ref codec) for details on all message types.

## Schema Validation

Validate raw payloads (as `Dict`) against the official OCPP JSON schemas before parsing into typed structs.

```@example guide
result = validate(:v16, "BootNotification", decoded.payload, :request)
isnothing(result)  # true — payload is valid
```

```@example guide
# Invalid payload: missing required field
result = validate(:v16, "BootNotification", Dict("chargePointVendor" => "V"), :request)
```

See [Validation](@ref validation) for the full API.

## Typical Message Flow

A typical OCPP message handling pipeline looks like:

```
WebSocket frame (raw JSON string)
  → decode(raw)               # parse wire format → Call/CallResult/CallError
  → validate(:v16, ...)       # validate payload against schema (optional)
  → JSON.parse(payload, T)    # deserialize Dict → typed struct
  → process(request)          # your application logic
  → JSON.json(response)       # serialize response struct → JSON
  → encode(CallResult(...))   # wrap in wire format → send back
```
