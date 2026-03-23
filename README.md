# OCPP.jl

[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSolarPV.github.io/OCPP.jl/dev)

[![Test workflow status](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSolarPV/OCPP.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSolarPV/OCPP.jl)
[![Lint workflow Status](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/JuliaSolarPV/OCPP.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)
[![tested with JET.jl](https://img.shields.io/badge/%F0%9F%9B%A9%EF%B8%8F_tested_with-JET.jl-233f9a)](https://github.com/aviatesk/JET.jl)

OCPP.jl is a Julia implementation of the [Open Charge Point Protocol](https://www.openchargealliance.org/) (OCPP), the standard communication protocol between electric vehicle charging stations and a central management system (CSMS).

All message types are auto-generated from the official OCPP JSON schema files — no hand-written structs. The package provides:

- **OCPP 1.6** — 28 actions, 56 request/response structs, 32 enum types
- **OCPP 2.0.1** — 64 actions, 128 request/response structs, 88 enum types
- **OCPP-J codec** — encode/decode the JSON-over-WebSocket wire format
- **Schema validation** — validate message payloads against official JSON schemas at runtime
- **Type-safe** — every OCPP message is a concrete Julia struct with proper field types
- **camelCase / snake_case** — automatic conversion between JSON wire format and Julia conventions

## Example Usage

```julia
julia> using OCPP, OCPP.V16, JSON

# Construct a typed request (snake_case in Julia)
julia> req = BootNotificationRequest(
           charge_point_vendor = "MyVendor",
           charge_point_model = "MyModel",
       )
BootNotificationRequest("MyModel", "MyVendor", nothing, nothing, nothing, nothing, nothing, nothing, nothing)

# Serialize to JSON (camelCase on the wire, optional fields as null)
julia> json_str = JSON.json(req)
"{\"chargePointModel\":\"MyModel\",\"chargePointVendor\":\"MyVendor\",\"chargeBoxSerialNumber\":null,...}"

# Deserialize back
julia> JSON.parse(json_str, BootNotificationRequest)
BootNotificationRequest("MyModel", "MyVendor", nothing, nothing, nothing, nothing, nothing, nothing, nothing)
```

### OCPP-J Wire Format

```julia
# Wrap in OCPP-J Call frame
julia> msg = Call("id-1", "BootNotification", Dict{String,Any}(
           "chargePointVendor" => "MyVendor",
           "chargePointModel" => "MyModel",
       ))
Call(2, "id-1", "BootNotification", Dict("chargePointVendor"=>"MyVendor", "chargePointModel"=>"MyModel"))

julia> wire = encode(msg)
"[2,\"id-1\",\"BootNotification\",{\"chargePointVendor\":\"MyVendor\",\"chargePointModel\":\"MyModel\"}]"

julia> decoded = decode(wire)
Call(2, "id-1", "BootNotification", Dict("chargePointVendor"=>"MyVendor", "chargePointModel"=>"MyModel"))

julia> decoded.action
"BootNotification"
```

### Schema Validation

```julia
# Validate a payload against the official JSON schema
julia> validate(:v16, "BootNotification", decoded.payload, :request)
# nothing — payload is valid

# Invalid payload: missing required field
julia> validate(:v16, "BootNotification", Dict("chargePointVendor" => "V"), :request)
"Validation failed:\npath:         top-level\ninstance:     ..."
```

### Enums

```julia
julia> resp = BootNotificationResponse(
           status = RegistrationAccepted,
           current_time = "2025-01-01T00:00:00Z",
           interval = 300,
       )

julia> JSON.json(resp)
"{\"currentTime\":\"2025-01-01T00:00:00Z\",\"interval\":300,\"status\":\"Accepted\"}"
```

## How to Cite

If you use OCPP.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/JuliaSolarPV/OCPP.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first take a look into our [contributing guide directly on GitHub](docs/src/90-contributing.md) or the [contributing page on the website](https://JuliaSolarPV.github.io/OCPP.jl/dev/90-contributing/).
