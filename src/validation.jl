"""
Runtime validation of OCPP message payloads against JSON schemas using JSONSchema.jl.

Schemas are lazy-loaded and cached on first use.
"""

import JSONSchema

# Lazy-loaded schema cache: version → "Action_msgtype" → JSONSchema.Schema
const _SCHEMA_CACHE = Dict{Symbol,Dict{String,JSONSchema.Schema}}()

const _V16_SCHEMA_DIR = joinpath(@__DIR__, "v16", "schemas")
const _V201_SCHEMA_DIR = joinpath(@__DIR__, "v201", "schemas")

function _load_schema(version::Symbol, action::String, msg_type::Symbol)
    if version == :v16
        # V16: "BootNotification.json" (request), "BootNotificationResponse.json"
        suffix = msg_type == :request ? "" : "Response"
        fname = "$(action)$(suffix).json"
        schema_dir = _V16_SCHEMA_DIR
    elseif version == :v201
        # V201: "BootNotificationRequest.json", "BootNotificationResponse.json"
        suffix = msg_type == :request ? "Request" : "Response"
        fname = "$(action)$(suffix).json"
        schema_dir = _V201_SCHEMA_DIR
    else
        throw(ArgumentError("Unknown OCPP version: $version (expected :v16 or :v201)"))
    end
    path = joinpath(schema_dir, fname)
    isfile(path) || throw(ArgumentError("No schema file found: $fname"))
    return JSONSchema.Schema(JSON.parse(read(path, String)))
end

function _get_schema(version::Symbol, action::String, msg_type::Symbol)
    cache = get!(_SCHEMA_CACHE, version) do
        Dict{String,JSONSchema.Schema}()
    end
    key = "$(action)_$(msg_type)"
    return get!(cache, key) do
        _load_schema(version, action, msg_type)
    end
end

"""
    validate(version::Symbol, action::String, payload::AbstractDict, msg_type::Symbol)

Validate an OCPP message payload against its JSON schema.

Returns `nothing` if the payload is valid, or a diagnostic string describing the
validation error.

# Arguments
- `version`: `:v16` or `:v201`
- `action`: Action name (e.g., `"BootNotification"`)
- `payload`: The message payload as a Dict
- `msg_type`: `:request` or `:response`

# Examples
```julia
result = validate(:v16, "BootNotification", payload, :request)
isnothing(result)  # true if valid
```
"""
function validate(
    version::Symbol,
    action::String,
    payload::AbstractDict,
    msg_type::Symbol,
)::Union{Nothing,String}
    schema = _get_schema(version, action, msg_type)
    result = JSONSchema.validate(schema, payload)
    return isnothing(result) ? nothing : string(result)
end
