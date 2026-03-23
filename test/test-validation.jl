@testitem "V16 valid BootNotification request" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "BootNotification",
        Dict("chargePointVendor" => "TestVendor", "chargePointModel" => "TestModel"),
        :request,
    )
    @test isnothing(result)
end

@testitem "V16 missing required field" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "BootNotification",
        Dict("chargePointVendor" => "TestVendor"),
        :request,
    )
    @test !isnothing(result)
    @test occursin("required", result)
end

@testitem "V16 wrong field type" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "BootNotification",
        Dict("chargePointVendor" => 123, "chargePointModel" => "M"),
        :request,
    )
    @test !isnothing(result)
    @test occursin("type", result)
end

@testitem "V16 HeartbeatRequest empty payload valid" tags = [:fast] begin
    using OCPP
    result = validate(:v16, "Heartbeat", Dict{String,Any}(), :request)
    @test isnothing(result)
end

@testitem "V16 response validation" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "BootNotification",
        Dict(
            "status" => "Accepted",
            "currentTime" => "2025-01-01T00:00:00Z",
            "interval" => 300,
        ),
        :response,
    )
    @test isnothing(result)
end

@testitem "V201 valid BootNotification request" tags = [:fast] begin
    using OCPP
    result = validate(
        :v201,
        "BootNotification",
        Dict(
            "reason" => "PowerUp",
            "chargingStation" => Dict("model" => "M", "vendorName" => "V"),
        ),
        :request,
    )
    @test isnothing(result)
end

@testitem "V201 missing required field" tags = [:fast] begin
    using OCPP
    result = validate(:v201, "BootNotification", Dict("reason" => "PowerUp"), :request)
    @test !isnothing(result)
    @test occursin("required", result)
end

@testitem "V201 response validation" tags = [:fast] begin
    using OCPP
    result = validate(
        :v201,
        "BootNotification",
        Dict(
            "status" => "Accepted",
            "currentTime" => "2025-01-01T00:00:00Z",
            "interval" => 300,
        ),
        :response,
    )
    @test isnothing(result)
end

@testitem "Unknown action throws ArgumentError" tags = [:fast] begin
    using OCPP
    @test_throws ArgumentError validate(
        :v16,
        "NonExistentAction",
        Dict{String,Any}(),
        :request,
    )
end

@testitem "Unknown version throws ArgumentError" tags = [:fast] begin
    using OCPP
    @test_throws ArgumentError validate(
        :v99,
        "BootNotification",
        Dict{String,Any}(),
        :request,
    )
end

@testitem "V16 SetChargingProfile with float limit passes validation" tags = [:fast] begin
    using OCPP
    payload = Dict{String,Any}(
        "connectorId" => 1,
        "csChargingProfiles" => Dict{String,Any}(
            "chargingProfileId" => 1,
            "stackLevel" => 0,
            "chargingProfilePurpose" => "TxProfile",
            "chargingProfileKind" => "Relative",
            "chargingSchedule" => Dict{String,Any}(
                "chargingRateUnit" => "A",
                "chargingSchedulePeriod" =>
                    [Dict{String,Any}("startPeriod" => 0, "limit" => 21.4)],
            ),
            "transactionId" => 123456789,
        ),
    )
    result = validate(:v16, "SetChargingProfile", payload, :request)
    @test isnothing(result)
end

@testitem "V16 StartTransaction idTag maxLength violation fails" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "StartTransaction",
        Dict{String,Any}(
            "connectorId" => 1,
            "idTag" => "012345678901234567890",  # 21 chars, max is 20
            "meterStart" => 0,
            "timestamp" => "2025-01-01T00:00:00Z",
        ),
        :request,
    )
    @test !isnothing(result)
end


@testitem "V16 BootNotification additional property fails validation" tags = [:fast] begin
    using OCPP
    result = validate(
        :v16,
        "BootNotification",
        Dict{String,Any}(
            "chargePointVendor" => "V",
            "chargePointModel" => "M",
            "unknownField" => "x",
        ),
        :request,
    )
    @test !isnothing(result)
end

@testitem "V201 BootNotification response wrong interval type fails" tags = [:fast] begin
    using OCPP
    result = validate(
        :v201,
        "BootNotification",
        Dict{String,Any}(
            "status" => "Accepted",
            "currentTime" => "2025-01-01T00:00:00Z",
            "interval" => "300",  # string instead of integer
        ),
        :response,
    )
    @test !isnothing(result)
end
