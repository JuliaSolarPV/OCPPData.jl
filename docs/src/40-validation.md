# [Schema Validation](@id validation)

## Overview

OCPP.jl includes a runtime validation layer powered by [JSONSchema.jl](https://github.com/fredo-dedup/JSONSchema.jl). This lets you validate raw message payloads (as `Dict`) against the official OCPP JSON schemas **before** attempting typed deserialization.

This is useful for:

- Validating incoming messages from untrusted charge points
- Providing clear error diagnostics (missing fields, wrong types, invalid enum values)
- Catching malformed messages early in the pipeline

## API

```julia
validate(spec::AbstractOCPPSpec, action::String, payload::AbstractDict, msg_type::Symbol)
```

| Argument | Values | Example |
|----------|--------|---------|
| `spec` | `V16.Spec()` or `V201.Spec()` | `V16.Spec()` |
| `action` | Action name | `"BootNotification"` |
| `payload` | Message payload as a Dict | `Dict("chargePointVendor" => "V", ...)` |
| `msg_type` | `:request` or `:response` | `:request` |

**Returns:** `nothing` if valid, or a `String` describing the validation error.

## Examples

```@example val
using OCPP, OCPP.V16, OCPP.V201
```

### Valid Payload

```@example val
result = validate(
    V16.Spec(),
    "BootNotification",
    Dict("chargePointVendor" => "V", "chargePointModel" => "M"),
    :request,
)
isnothing(result)
```

### Missing Required Field

```@example val
validate(
    V16.Spec(),
    "BootNotification",
    Dict("chargePointVendor" => "V"),
    :request,
)
```

### Wrong Field Type

```@example val
validate(
    V16.Spec(),
    "BootNotification",
    Dict("chargePointVendor" => 123, "chargePointModel" => "M"),
    :request,
)
```

### V16 Response Validation

```@example val
result = validate(
    V16.Spec(),
    "BootNotification",
    Dict(
        "status" => "Accepted",
        "currentTime" => "2025-01-01T00:00:00Z",
        "interval" => 300,
    ),
    :response,
)
isnothing(result)
```

### V201 Validation

```@example val
result = validate(
    V201.Spec(),
    "BootNotification",
    Dict(
        "reason" => "PowerUp",
        "chargingStation" => Dict("model" => "M", "vendorName" => "V"),
    ),
    :request,
)
isnothing(result)
```

### Empty Payload (HeartbeatRequest)

```@example val
result = validate(V16.Spec(), "Heartbeat", Dict{String,Any}(), :request)
isnothing(result)
```

## How It Works

Schemas are **lazy-loaded and cached** on first use. The first call to `validate` for a given action reads the JSON schema file from disk and compiles it into a `JSONSchema.Schema` object. Subsequent calls for the same action reuse the cached schema.

Schema files are resolved based on version-specific naming conventions, encoded via multiple dispatch on the `Spec` type:

- **V16**: `BootNotification.json` (request), `BootNotificationResponse.json` (response)
- **V201**: `BootNotificationRequest.json`, `BootNotificationResponse.json`

!!! note "Validation vs typed parsing"
    `validate` checks the raw `Dict` payload against the JSON schema. It does **not** convert the payload to a typed struct. Use `JSON.parse(json_str, T)` for typed deserialization after validation passes.
