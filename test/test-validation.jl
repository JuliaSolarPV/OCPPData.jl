@testitem "Schema validation" tags = [:fast] begin
    using OCPPData
    using Test

    @testset "V16 BootNotification" begin
        @test isnothing(
            validate(
                V16.Spec(),
                "BootNotification",
                Dict(
                    "chargePointVendor" => "TestVendor",
                    "chargePointModel" => "TestModel",
                ),
                :request,
            ),
        )
        # missing required field
        result = validate(
            V16.Spec(),
            "BootNotification",
            Dict("chargePointVendor" => "V"),
            :request,
        )
        @test !isnothing(result)
        @test occursin("required", result)
        # wrong field type
        result = validate(
            V16.Spec(),
            "BootNotification",
            Dict("chargePointVendor" => 123, "chargePointModel" => "M"),
            :request,
        )
        @test !isnothing(result)
        @test occursin("type", result)
        # additional properties not allowed
        result = validate(
            V16.Spec(),
            "BootNotification",
            Dict(
                "chargePointVendor" => "V",
                "chargePointModel" => "M",
                "unknownField" => "x",
            ),
            :request,
        )
        @test !isnothing(result)
    end

    @testset "V16 BootNotification response" begin
        @test isnothing(
            validate(
                V16.Spec(),
                "BootNotification",
                Dict(
                    "status" => "Accepted",
                    "currentTime" => "2025-01-01T00:00:00Z",
                    "interval" => 300,
                ),
                :response,
            ),
        )
    end

    @testset "V16 Heartbeat empty payload" begin
        @test isnothing(validate(V16.Spec(), "Heartbeat", Dict{String,Any}(), :request))
    end

    @testset "V16 StartTransaction maxLength violation" begin
        result = validate(
            V16.Spec(),
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

    @testset "V16 SetChargingProfile float limit" begin
        result = validate(
            V16.Spec(),
            "SetChargingProfile",
            Dict{String,Any}(
                "connectorId" => 1,
                "csChargingProfiles" => Dict{String,Any}(
                    "chargingProfileId" => 1,
                    "stackLevel" => 0,
                    "chargingProfilePurpose" => "TxProfile",
                    "chargingProfileKind" => "Relative",
                    "chargingSchedule" => Dict{String,Any}(
                        "chargingRateUnit" => "A",
                        "chargingSchedulePeriod" => [
                            Dict{String,Any}("startPeriod" => 0, "limit" => 21.4),
                        ],
                    ),
                    "transactionId" => 123456789,
                ),
            ),
            :request,
        )
        @test isnothing(result)
    end

    @testset "V201 BootNotification" begin
        @test isnothing(
            validate(
                V201.Spec(),
                "BootNotification",
                Dict(
                    "reason" => "PowerUp",
                    "chargingStation" => Dict("model" => "M", "vendorName" => "V"),
                ),
                :request,
            ),
        )
        # missing required field
        result =
            validate(V201.Spec(), "BootNotification", Dict("reason" => "PowerUp"), :request)
        @test !isnothing(result)
        @test occursin("required", result)
    end

    @testset "V201 BootNotification response" begin
        @test isnothing(
            validate(
                V201.Spec(),
                "BootNotification",
                Dict(
                    "status" => "Accepted",
                    "currentTime" => "2025-01-01T00:00:00Z",
                    "interval" => 300,
                ),
                :response,
            ),
        )
        # wrong type for interval
        result = validate(
            V201.Spec(),
            "BootNotification",
            Dict(
                "status" => "Accepted",
                "currentTime" => "2025-01-01T00:00:00Z",
                "interval" => "300",
            ),
            :response,
        )
        @test !isnothing(result)
    end

    @testset "Error cases" begin
        @test_throws ArgumentError validate(
            V16.Spec(),
            "NonExistentAction",
            Dict{String,Any}(),
            :request,
        )
        # Unknown spec type → MethodError (no _load_schema method defined for it)
        struct UnknownSpec <: OCPPData.AbstractOCPPSpec end
        @test_throws MethodError validate(
            UnknownSpec(),
            "BootNotification",
            Dict{String,Any}(),
            :request,
        )
    end
end
