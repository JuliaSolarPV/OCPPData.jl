"""
Runtime validation of OCPP message payloads against JSON schemas using JSONSchema.jl.

Schemas are eagerly loaded at module init time into per-version dictionaries.
Version-specific behaviour (schema directory, filename convention) is resolved via
multiple dispatch on the concrete `AbstractOCPPSpec` subtype.
"""

import JSONSchema

"""
    _load_all_schemas!(schemas, schema_dir, actions, filename_fn)

Eagerly load all JSON schemas for a given OCPP version into `schemas`.

Iterates every action in `actions` and both message types (`:request`, `:response`),
reads the JSON file, and stores the parsed `JSONSchema.Schema`.
"""
function _load_all_schemas!(
    schemas::Dict{String,JSONSchema.Schema},
    schema_dir::String,
    actions::Dict{String,<:NamedTuple},
    filename_fn,
)::Nothing
    for action in keys(actions)
        for msg_type in (:request, :response)
            fname = filename_fn(action, msg_type)
            path = joinpath(schema_dir, fname)
            isfile(path) || continue
            key = "$(action)_$(msg_type)"
            schemas[key] = JSONSchema.Schema(JSON.parse(read(path, String)))
        end
    end
    return nothing
end

if ENABLE_V16
    function _get_schema(::V16.Spec, action::String, msg_type::Symbol)
        key = "$(action)_$(msg_type)"
        haskey(V16._SCHEMAS, key) ||
            throw(ArgumentError("No schema found for action: $action ($msg_type)"))
        return V16._SCHEMAS[key]
    end
end

if ENABLE_V201
    function _get_schema(::V201.Spec, action::String, msg_type::Symbol)
        key = "$(action)_$(msg_type)"
        haskey(V201._SCHEMAS, key) ||
            throw(ArgumentError("No schema found for action: $action ($msg_type)"))
        return V201._SCHEMAS[key]
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
