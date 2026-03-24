"""
OCPP-J message framing types.

The OCPP-J protocol uses JSON arrays with a message type ID as the first element:
- [2, unique_id, action, payload]       → Call
- [3, unique_id, payload]               → CallResult
- [4, unique_id, error_code, desc, det] → CallError
"""
abstract type OCPPMessage end

struct Call <: OCPPMessage
    message_type_id::Int
    unique_id::String
    action::String
    payload::Dict{String,Any}
end

struct CallResult <: OCPPMessage
    message_type_id::Int
    unique_id::String
    payload::Dict{String,Any}
end

struct CallError <: OCPPMessage
    message_type_id::Int
    unique_id::String
    error_code::String
    error_description::String
    error_details::Dict{String,Any}
end

# Convenience constructors that auto-fill message_type_id
function Call(unique_id::String, action::String, payload::Dict{String,Any})
    return Call(2, unique_id, action, payload)
end

function CallResult(unique_id::String, payload::Dict{String,Any})
    return CallResult(3, unique_id, payload)
end

function CallError(
    unique_id::String,
    error_code::String,
    error_description::String,
    error_details::Dict{String,Any},
)
    return CallError(4, unique_id, error_code, error_description, error_details)
end

"""
Abstract base type for OCPP protocol version specifiers.

Concrete subtypes (`V16.Spec`, `V201.Spec`) are used as dispatch tokens to select
version-specific behaviour — e.g. `validate(V16.Spec(), ...)`.
"""
abstract type AbstractOCPPSpec end
