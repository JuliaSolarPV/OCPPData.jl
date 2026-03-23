module OCPP

using JSON
using StructUtils
using UUIDs
using PrecompileTools

# Protocol-level message types (version-independent)
include("messages.jl")

# Codec: encode/decode OCPP-J wire format
include("codec.jl")

# Version-agnostic schema reader
include("schema_reader.jl")

# OCPP 1.6 submodule
module V16
using StructUtils
using JSON
using ..OCPP: @generate_ocpp_types

include("v16/registries.jl")

const _SCHEMA_DIR = joinpath(@__DIR__, "v16", "schemas")
@generate_ocpp_types _SCHEMA_DIR V16_ENUM_REGISTRY V16_NESTED_TYPE_NAMES :V16_ACTIONS
end # module V16

# OCPP 2.0.1 submodule
module V201
using StructUtils
using JSON
using ..OCPP: @generate_ocpp_types_from_definitions

const _SCHEMA_DIR = joinpath(@__DIR__, "v201", "schemas")
@generate_ocpp_types_from_definitions _SCHEMA_DIR :V201_ACTIONS
end # module V201

# Schema validation
include("validation.jl")

# Exports — protocol-level
export OCPPMessage, Call, CallResult, CallError
export encode, decode, generate_unique_id, validate

# Re-export version submodules
export V16, V201

# Precompile common operations to reduce TTFX
@compile_workload begin
    # Codec round-trip
    msg = Call("test-id", "Heartbeat", Dict{String,Any}())
    raw = encode(msg)
    decode(raw)

    # V16 type construction and JSON round-trip
    req = V16.HeartbeatRequest()
    JSON.json(req)

    # Action registry
    V16.request_type("Heartbeat")
    V16.response_type("Heartbeat")

    # Schema validation
    validate(
        :v16,
        "BootNotification",
        Dict{String,Any}("chargePointVendor" => "V", "chargePointModel" => "M"),
        :request,
    )
end

end # module OCPP
