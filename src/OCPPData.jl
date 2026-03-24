module OCPPData

using JSON
using StructUtils
using UUIDs
using PrecompileTools
using Preferences

# Protocol version preference: "all" (default), "v16", or "v201"
const PROTOCOL_VERSION = @load_preference("protocol_version", "all")
const ENABLE_V16 = PROTOCOL_VERSION in ("v16", "all")
const ENABLE_V201 = PROTOCOL_VERSION in ("v201", "all")

# Protocol-level message types (version-independent)
include("messages.jl")

# Codec: encode/decode OCPP-J wire format
include("codec.jl")

# Version-agnostic schema reader
include("schema_reader.jl")

# OCPP 1.6 submodule
if ENABLE_V16
    include("v16/V16.jl")
end

# OCPP 2.0.1 submodule
if ENABLE_V201
    include("v201/V201.jl")
end

# Schema validation
include("validation.jl")

# Eagerly load all schemas at module init time
if ENABLE_V16
    _load_all_schemas!(
        V16._SCHEMAS,
        V16._SCHEMA_DIR,
        V16.V16_ACTIONS,
        (a, mt) -> mt == :request ? "$(a).json" : "$(a)Response.json",
    )
end
if ENABLE_V201
    _load_all_schemas!(
        V201._SCHEMAS,
        V201._SCHEMA_DIR,
        V201.V201_ACTIONS,
        (a, mt) -> mt == :request ? "$(a)Request.json" : "$(a)Response.json",
    )
end

# Exports — protocol-level
export OCPPMessage, Call, CallResult, CallError
export AbstractOCPPSpec
export encode, decode, generate_unique_id, validate

# Re-export version submodules
if ENABLE_V16
    export V16
end
if ENABLE_V201
    export V201
end

# Precompile common operations to reduce TTFX
@compile_workload begin
    # Codec round-trip (always)
    msg = Call("test-id", "Heartbeat", Dict{String,Any}())
    raw = encode(msg)
    decode(raw)
end

if ENABLE_V16
    @compile_workload begin
        # V16 type construction and JSON round-trip
        req = V16.HeartbeatRequest()
        JSON.json(req)

        boot = V16.BootNotificationRequest(
            charge_point_vendor = "TestVendor",
            charge_point_model = "TestModel",
        )
        json_str = JSON.json(boot)
        JSON.parse(json_str, V16.BootNotificationRequest)

        # Action registry
        V16.request_type("Heartbeat")
        V16.response_type("Heartbeat")

        # Schema validation — V16 request + response
        validate(
            V16.Spec(),
            "BootNotification",
            Dict{String,Any}("chargePointVendor" => "V", "chargePointModel" => "M"),
            :request,
        )
        validate(
            V16.Spec(),
            "BootNotification",
            Dict{String,Any}(
                "status" => "Accepted",
                "currentTime" => "2025-01-01T00:00:00Z",
                "interval" => 300,
            ),
            :response,
        )
    end
end

if ENABLE_V201
    @compile_workload begin
        # Schema validation — V201 request + response
        validate(
            V201.Spec(),
            "BootNotification",
            Dict{String,Any}(
                "reason" => "PowerUp",
                "chargingStation" => Dict{String,Any}("vendorName" => "V", "model" => "M"),
            ),
            :request,
        )
        validate(
            V201.Spec(),
            "BootNotification",
            Dict{String,Any}(
                "status" => "Accepted",
                "currentTime" => "2025-01-01T00:00:00.000Z",
                "interval" => 300,
            ),
            :response,
        )
    end
end

end # module OCPPData
