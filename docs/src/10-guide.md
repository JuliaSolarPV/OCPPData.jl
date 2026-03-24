# Usage Guide

## Protocol Version Selection

By default, OCPPData.jl loads both OCPP 1.6 and OCPP 2.0.1 types and schemas. If you only need one version, you can reduce load time and memory usage by setting the `protocol_version` preference via [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl).

The preference is a compile-time constant, so it must be set **before** loading OCPPData. Create a `LocalPreferences.toml` file in your project root:

```toml
[OCPPData]
protocol_version = "v16"    # or "v201" or "all"
```

Valid values:

- `"all"` (default) — load both V16 and V201
- `"v16"` — load only OCPP 1.6
- `"v201"` — load only OCPP 2.0.1

You can also set the preference programmatically. Since the preference is read at compile time, you must set it in a separate Julia session before loading OCPPData:

```julia
# Session 1: set the preference
using Preferences
set_preferences!("OCPPData", "protocol_version" => "v16"; force = true)
```

```julia
# Session 2: OCPPData now loads only V16
using OCPPData
isdefined(OCPPData, :V16)   # true
isdefined(OCPPData, :V201)  # false
```

!!! warning "Version availability"
    When a version is disabled, its submodule (`V16` or `V201`) is not defined. Code that references a disabled version will error. Make sure your tests and application code match the configured version.

## Working with OCPP Types

OCPPData.jl provides typed Julia structs for every OCPP message. Types live in version-specific submodules: `OCPPData.V16` (28 actions) and `OCPPData.V201` (64 actions).

```@example guide
using OCPPData
using OCPPData.V16  # brings BootNotificationRequest, HeartbeatRequest, etc. into scope
import JSON     # use import (not using) to avoid conflict with V201's JSON enum member
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
using OCPPData
import JSON
station = OCPPData.V201.ChargingStation(model = "M", vendor_name = "V")
req201 = OCPPData.V201.BootNotificationRequest(
    reason = OCPPData.V201.BootReasonPowerUp,
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
length(V16.V16_ACTIONS), length(OCPPData.V201.V201_ACTIONS)
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
result = validate(V16.Spec(), "BootNotification", decoded.payload, :request)
isnothing(result)  # true — payload is valid
```

```@example guide
# Invalid payload: missing required field
result = validate(V16.Spec(), "BootNotification", Dict("chargePointVendor" => "V"), :request)
```

See [Validation](@ref validation) for the full API.

## Typical Message Flow

A typical OCPP message handling pipeline looks like:

```text
WebSocket frame (raw JSON string)
  → decode(raw)               # parse wire format → Call/CallResult/CallError
  → validate(V16.Spec(), ...) # validate payload against schema (optional)
  → JSON.parse(payload, T)    # deserialize Dict → typed struct
  → process(request)          # your application logic
  → JSON.json(response)       # serialize response struct → JSON
  → encode(CallResult(...))   # wrap in wire format → send back
```
