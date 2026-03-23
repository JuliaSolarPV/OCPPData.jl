@testitem "Encode Call" tags = [:fast] begin
    using OCPP
    using JSON
    msg = Call("uid-1", "Heartbeat", Dict{String,Any}())
    json = encode(msg)
    arr = JSON.parse(json)
    @test arr[1] == 2
    @test arr[2] == "uid-1"
    @test arr[3] == "Heartbeat"
end

@testitem "Encode CallResult" tags = [:fast] begin
    using OCPP
    using JSON
    msg = CallResult("uid-1", Dict{String,Any}("status" => "Accepted"))
    json = encode(msg)
    arr = JSON.parse(json)
    @test arr[1] == 3
    @test arr[2] == "uid-1"
end

@testitem "Encode CallError" tags = [:fast] begin
    using OCPP
    using JSON
    msg = CallError("uid-1", "InternalError", "oops", Dict{String,Any}())
    json = encode(msg)
    arr = JSON.parse(json)
    @test arr[1] == 4
    @test arr[2] == "uid-1"
    @test arr[3] == "InternalError"
    @test arr[4] == "oops"
end

@testitem "Decode Call round-trip" tags = [:fast] begin
    using OCPP
    original = Call("uid-1", "Reset", Dict{String,Any}("type" => "Hard"))
    decoded = decode(encode(original))
    @test decoded isa Call
    @test decoded.unique_id == original.unique_id
    @test decoded.action == original.action
    @test decoded.payload == original.payload
end

@testitem "Decode CallResult round-trip" tags = [:fast] begin
    using OCPP
    original =
        CallResult("uid-2", Dict{String,Any}("currentTime" => "2025-01-01T00:00:00Z"))
    decoded = decode(encode(original))
    @test decoded isa CallResult
    @test decoded.unique_id == original.unique_id
    @test decoded.payload == original.payload
end

@testitem "Decode CallError round-trip" tags = [:fast] begin
    using OCPP
    original = CallError("uid-3", "NotSupported", "nope", Dict{String,Any}("x" => 1))
    decoded = decode(encode(original))
    @test decoded isa CallError
    @test decoded.unique_id == original.unique_id
    @test decoded.error_code == original.error_code
    @test decoded.error_description == original.error_description
    @test decoded.error_details == original.error_details
end

@testitem "Decode unknown type_id throws" tags = [:fast] begin
    using OCPP
    @test_throws ArgumentError decode("[99,\"id\",\"Action\",{}]")
end

@testitem "Decode nested payload" tags = [:fast] begin
    using OCPP
    raw = """[2,"uid","MeterValues",{"connectorId":1,"meterValue":[{"timestamp":"2025-01-01T00:00:00Z","sampledValue":[{"value":"100"}]}]}]"""
    msg = decode(raw)
    @test msg isa Call
    mv = msg.payload["meterValue"]
    @test mv isa Vector
    @test mv[1]["sampledValue"][1]["value"] == "100"
end

@testitem "generate_unique_id returns UUID string" tags = [:fast] begin
    using OCPP
    uid = generate_unique_id()
    @test length(uid) == 36  # UUID format: 8-4-4-4-12
    @test count(==('-'), uid) == 4
end

@testitem "Decode invalid JSON throws" tags = [:fast] begin
    using OCPP
    @test_throws Exception decode("not-json {{{")
end

@testitem "Decode non-array JSON throws" tags = [:fast] begin
    using OCPP
    @test_throws Exception decode("{\"key\":\"value\"}")
end

@testitem "Encode/decode preserves bool, float, and array payload" tags = [:fast] begin
    using OCPP
    payload = Dict{String,Any}("flag" => true, "limit" => 21.4, "ids" => Any[1, 2, 3])
    original = Call("uid-x", "SetChargingProfile", payload)
    decoded = decode(encode(original))
    @test decoded.payload["flag"] === true
    @test decoded.payload["limit"] ≈ 21.4
    @test decoded.payload["ids"] == [1, 2, 3]
end

@testitem "CallError encode/decode with non-empty details" tags = [:fast] begin
    using OCPP
    original =
        CallError("uid-e", "InternalError", "details matter", Dict{String,Any}("key" => "val"))
    decoded = decode(encode(original))
    @test decoded isa CallError
    @test decoded.error_details["key"] == "val"
end
