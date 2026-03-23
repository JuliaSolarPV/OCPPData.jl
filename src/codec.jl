"""
OCPP-J codec: encode/decode between OCPPMessage types and JSON wire format.
"""

"""
    encode(msg::Call)::String

Encode a Call message to OCPP-J JSON array format: `[2, unique_id, action, payload]`.
"""
function encode(msg::Call)::String
    return JSON.json([msg.message_type_id, msg.unique_id, msg.action, msg.payload],)
end

"""
    encode(msg::CallResult)::String

Encode a CallResult to OCPP-J JSON array format: `[3, unique_id, payload]`.
"""
function encode(msg::CallResult)::String
    return JSON.json([msg.message_type_id, msg.unique_id, msg.payload],)
end

"""
    encode(msg::CallError)::String

Encode a CallError to OCPP-J JSON array format:
`[4, unique_id, error_code, error_description, error_details]`.
"""
function encode(msg::CallError)::String
    return JSON.json([
        msg.message_type_id,
        msg.unique_id,
        msg.error_code,
        msg.error_description,
        msg.error_details,
    ])
end

"""
    decode(raw::String)::OCPPMessage

Decode a raw OCPP-J JSON string into the appropriate OCPPMessage subtype.
Dispatches on the first element (message type ID): 2=Call, 3=CallResult, 4=CallError.
"""
function decode(raw::String)::OCPPMessage
    arr = JSON.parse(raw)
    type_id = arr[1]
    if type_id == 2
        return Call(2, String(arr[2]), String(arr[3]), _to_dict(arr[4]))
    elseif type_id == 3
        return CallResult(3, String(arr[2]), _to_dict(arr[3]))
    elseif type_id == 4
        return CallError(
            4,
            String(arr[2]),
            String(arr[3]),
            String(arr[4]),
            _to_dict(arr[5]),
        )
    else
        throw(ArgumentError("Unknown OCPP message type ID: $type_id"))
    end
end

"""
    generate_unique_id()::String

Generate a UUID string for use as an OCPP message unique_id.
"""
function generate_unique_id()::String
    return string(uuid4())
end

# Convert any AbstractDict to Dict{String,Any}, recursively.
function _to_dict(obj)::Dict{String,Any}
    result = Dict{String,Any}()
    for (k, v) in pairs(obj)
        result[String(k)] = _convert_value(v)
    end
    return result
end

function _convert_value(v)
    if v isa AbstractDict
        return _to_dict(v)
    elseif v isa AbstractVector
        return Any[_convert_value(item) for item in v]
    else
        return v
    end
end
