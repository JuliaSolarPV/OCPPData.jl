# [OCPP-J Codec](@id codec)

## Wire Format

The OCPP-J protocol (JSON over WebSocket) uses JSON arrays with a message type ID as the first element:

| Type | ID | Format | Purpose |
|------|----|--------|---------|
| `Call` | 2 | `[2, unique_id, action, payload]` | Request from client or server |
| `CallResult` | 3 | `[3, unique_id, payload]` | Successful response |
| `CallError` | 4 | `[4, unique_id, error_code, description, details]` | Error response |

The `unique_id` correlates a `CallResult` or `CallError` back to its originating `Call`.

## Message Types

```@example codec
using OCPP
```

The three concrete subtypes of `OCPPMessage`:

```@example codec
using InteractiveUtils: subtypes
subtypes(OCPPMessage)
```

## Constructing Messages

Convenience constructors auto-fill `message_type_id`:

```@example codec
call = Call("id-1", "Heartbeat", Dict{String,Any}())
```

```@example codec
result = CallResult("id-1", Dict{String,Any}("status" => "Accepted"))
```

```@example codec
error = CallError("id-1", "NotImplemented", "Not supported", Dict{String,Any}())
```

## Encoding

`encode` converts an `OCPPMessage` to a JSON string ready for WebSocket transmission:

```@example codec
encode(call)
```

```@example codec
encode(result)
```

```@example codec
encode(error)
```

## Decoding

`decode` parses a raw JSON string back into the appropriate `OCPPMessage` subtype:

```@example codec
decoded = decode("[2,\"id-1\",\"Heartbeat\",{}]")
```

```@example codec
decoded isa Call
```

```@example codec
decoded.action
```

```@example codec
decoded.payload
```

Decoding a `CallResult`:

```@example codec
decode("[3,\"id-1\",{\"status\":\"Accepted\"}]")
```

Decoding a `CallError`:

```@example codec
decode("[4,\"id-1\",\"NotImplemented\",\"Not supported\",{}]")
```

## Round-Trip

```@example codec
msg = Call("abc-123", "BootNotification", Dict{String,Any}(
    "chargePointVendor" => "V",
    "chargePointModel" => "M",
))
wire = encode(msg)
```

```@example codec
decoded = decode(wire)
decoded.action, decoded.payload
```

## Generating Unique IDs

```@example codec
id = generate_unique_id()
println(id)  # UUID v4 string
length(id)   # 36 characters (8-4-4-4-12 format)
```
