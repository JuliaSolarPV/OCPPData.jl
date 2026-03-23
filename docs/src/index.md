```@meta
CurrentModule = OCPP
```

# OCPP.jl

A Julia implementation of the [Open Charge Point Protocol](https://www.openchargealliance.org/) (OCPP), the standard communication protocol between electric vehicle charging stations and a central management system (CSMS).

## Features

- **OCPP 1.6** — 28 actions, all request/response types auto-generated from JSON schemas
- **OCPP 2.0.1** — 64 actions, all request/response types auto-generated from JSON schemas
- **JSON codec** — encode/decode OCPP-J wire format (JSON over WebSocket)
- **Schema validation** — validate message payloads against official JSON schemas at runtime
- **Type-safe** — every OCPP message is a concrete Julia struct with proper field types
- **camelCase ↔ snake\_case** — automatic conversion between JSON wire format and Julia conventions

## Quick Start

```julia
using Pkg
Pkg.add("OCPP")
```

```@example quickstart
using OCPP
using OCPP.V16
import JSON

# Construct a typed request
req = BootNotificationRequest(
    charge_point_vendor = "MyVendor",
    charge_point_model = "MyModel",
)
```

```@example quickstart
# Serialize to JSON (camelCase on the wire)
json_str = JSON.json(req)
```

```@example quickstart
# Deserialize back
req2 = JSON.parse(json_str, BootNotificationRequest)
req == req2
```

```@example quickstart
# Encode/decode OCPP-J wire format
payload = Dict{String,Any}("chargePointVendor" => "MyVendor", "chargePointModel" => "MyModel")
msg = Call("unique-id-1", "BootNotification", payload)
wire = encode(msg)
```

```@example quickstart
decoded = decode(wire)
decoded.action
```

```@example quickstart
# Validate against JSON schema
result = validate(:v16, "BootNotification", decoded.payload, :request)
isnothing(result)  # true — payload is valid
```

## Package Structure

```
OCPP
├── Call, CallResult, CallError     # Wire-level message types
├── encode(), decode()              # OCPP-J codec
├── validate()                      # JSON Schema validation
├── V16                             # OCPP 1.6 submodule
│   ├── 28 action Request/Response structs
│   ├── 32 enum types
│   ├── V16_ACTIONS registry
│   └── request_type(), response_type()
└── V201                            # OCPP 2.0.1 submodule
    ├── 64 action Request/Response structs
    ├── 88 enum types
    ├── V201_ACTIONS registry
    └── request_type(), response_type()
```

## Contributors

```@raw html
<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
```
