"""
Runtime validation of OCPP message payloads against JSON schemas using JSONSchema.jl.

Schemas are lazy-loaded and cached on first use. Version-specific behaviour
(schema directory, filename convention) is resolved via multiple dispatch on
the `AbstractOCPPSpec` subtype passed as the first argument.
"""

import JSONSchema

# Lazy-loaded schema cache: spec type → "Action_msgtype" → JSONSchema.Schema
const _SCHEMA_CACHE = Dict{DataType,Dict{String,JSONSchema.Schema}}()

function _load_schema(::V16.Spec, action::String, msg_type::Symbol)
    # V16: "BootNotification.json" (request), "BootNotificationResponse.json" (response)
    suffix = msg_type == :request ? "" : "Response"
    fname = "$(action)$(suffix).json"
    path = joinpath(V16._SCHEMA_DIR, fname)
    isfile(path) || throw(ArgumentError("No schema file found: $fname"))
    return JSONSchema.Schema(JSON.parse(read(path, String)))
end

function _load_schema(::V201.Spec, action::String, msg_type::Symbol)
    # V201: "BootNotificationRequest.json", "BootNotificationResponse.json"
    suffix = msg_type == :request ? "Request" : "Response"
    fname = "$(action)$(suffix).json"
    path = joinpath(V201._SCHEMA_DIR, fname)
    isfile(path) || throw(ArgumentError("No schema file found: $fname"))
    return JSONSchema.Schema(JSON.parse(read(path, String)))
end

function _get_schema(spec::AbstractOCPPSpec, action::String, msg_type::Symbol)
    cache = get!(_SCHEMA_CACHE, typeof(spec)) do
        Dict{String,JSONSchema.Schema}()
    end
    key = "$(action)_$(msg_type)"
    return get!(cache, key) do
        _load_schema(spec, action, msg_type)
    end
end

"""
    validate(spec::AbstractOCPPSpec, action::String, payload::AbstractDict, msg_type::Symbol)

Validate an OCPP message payload against its JSON schema.

Returns `nothing` if the payload is valid, or a diagnostic string describing the
validation error.

# Arguments
- `spec`: Version spec instance — `V16.Spec()` or `V201.Spec()`
- `action`: Action name (e.g., `"BootNotification"`)
- `payload`: The message payload as a Dict
- `msg_type`: `:request` or `:response`

# Examples
```julia
result = validate(V16.Spec(), "BootNotification", payload, :request)
isnothing(result)  # true if valid

result = validate(V201.Spec(), "BootNotification", payload, :response)
isnothing(result)  # true if valid
```
"""
function validate(
    spec::AbstractOCPPSpec,
    action::String,
    payload::AbstractDict,
    msg_type::Symbol,
)::Union{Nothing,String}
    schema = _get_schema(spec, action, msg_type)
    result = JSONSchema.validate(schema, payload)
    return isnothing(result) ? nothing : string(result)
end
