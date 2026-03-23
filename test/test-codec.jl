@testitem "Codec" tags = [:fast] begin
    using OCPP
    using JSON
    using Test

    @testset "Encode Call" begin
        msg = Call("uid-1", "Heartbeat", Dict{String,Any}())
        arr = JSON.parse(encode(msg))
        @test arr[1] == 2
        @test arr[2] == "uid-1"
        @test arr[3] == "Heartbeat"
    end

    @testset "Encode CallResult" begin
        msg = CallResult("uid-1", Dict{String,Any}("status" => "Accepted"))
        arr = JSON.parse(encode(msg))
        @test arr[1] == 3
        @test arr[2] == "uid-1"
    end

    @testset "Encode CallError" begin
        msg = CallError("uid-1", "InternalError", "oops", Dict{String,Any}())
        arr = JSON.parse(encode(msg))
        @test arr[1] == 4
        @test arr[2] == "uid-1"
        @test arr[3] == "InternalError"
        @test arr[4] == "oops"
    end

    @testset "Decode Call round-trip" begin
        original = Call("uid-1", "Reset", Dict{String,Any}("type" => "Hard"))
        decoded = decode(encode(original))
        @test decoded isa Call
        @test decoded.unique_id == original.unique_id
        @test decoded.action == original.action
        @test decoded.payload == original.payload
    end

    @testset "Decode CallResult round-trip" begin
        original =
            CallResult("uid-2", Dict{String,Any}("currentTime" => "2025-01-01T00:00:00Z"))
        decoded = decode(encode(original))
        @test decoded isa CallResult
        @test decoded.unique_id == original.unique_id
        @test decoded.payload == original.payload
    end

    @testset "Decode CallError round-trip" begin
        original = CallError("uid-3", "NotSupported", "nope", Dict{String,Any}("x" => 1))
        decoded = decode(encode(original))
        @test decoded isa CallError
        @test decoded.unique_id == original.unique_id
        @test decoded.error_code == original.error_code
        @test decoded.error_description == original.error_description
        @test decoded.error_details == original.error_details
    end

    @testset "Decode unknown type_id throws" begin
        @test_throws ArgumentError decode("[99,\"id\",\"Action\",{}]")
    end

    @testset "Decode nested payload" begin
        raw = """[2,"uid","MeterValues",{"connectorId":1,"meterValue":[{"timestamp":"2025-01-01T00:00:00Z","sampledValue":[{"value":"100"}]}]}]"""
        msg = decode(raw)
        @test msg isa Call
        mv = msg.payload["meterValue"]
        @test mv isa Vector
        @test mv[1]["sampledValue"][1]["value"] == "100"
    end

    @testset "generate_unique_id" begin
        uid = generate_unique_id()
        @test length(uid) == 36
        @test count(==('-'), uid) == 4
    end

    @testset "Decode invalid JSON throws" begin
        @test_throws Exception decode("not-json {{{")
    end

    @testset "Decode non-array JSON throws" begin
        @test_throws Exception decode("{\"key\":\"value\"}")
    end

    @testset "Preserves bool, float, and array payload" begin
        payload = Dict{String,Any}("flag" => true, "limit" => 21.4, "ids" => Any[1, 2, 3])
        decoded = decode(encode(Call("uid-x", "SetChargingProfile", payload)))
        @test decoded.payload["flag"] === true
        @test decoded.payload["limit"] ≈ 21.4
        @test decoded.payload["ids"] == [1, 2, 3]
    end

    @testset "CallError with non-empty details" begin
        original = CallError(
            "uid-e",
            "InternalError",
            "details matter",
            Dict{String,Any}("key" => "val"),
        )
        decoded = decode(encode(original))
        @test decoded isa CallError
        @test decoded.error_details["key"] == "val"
    end
end
