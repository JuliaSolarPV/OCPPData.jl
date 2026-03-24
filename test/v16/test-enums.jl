@testitem "V16 Enums" tags = [:fast] begin
    using OCPPData.V16
    using JSON
    using Test

    @testset "string() produces OCPP value" begin
        @test string(RegistrationAccepted) == "Accepted"
        @test string(RegistrationPending) == "Pending"
        @test string(RegistrationRejected) == "Rejected"
        @test string(NoError) == "NoError"
        @test string(ResetHard) == "Hard"
        @test string(ResetSoft) == "Soft"
        @test string(MeasurandEnergyActiveImportRegister) == "Energy.Active.Import.Register"
        @test string(PhaseL1N) == "L1-N"
        @test string(ReadingInterruptionBegin) == "Interruption.Begin"
    end

    @testset "JSON write" begin
        @test JSON.json(RegistrationAccepted) == "\"Accepted\""
        @test JSON.json(ResetHard) == "\"Hard\""
        @test JSON.json(ChargingRateA) == "\"A\""
        @test JSON.json(MeasurandEnergyActiveImportRegister) ==
              "\"Energy.Active.Import.Register\""
    end

    @testset "JSON read" begin
        @test JSON.parse("\"Accepted\"", RegistrationStatus) == RegistrationAccepted
        @test JSON.parse("\"Pending\"", RegistrationStatus) == RegistrationPending
        @test JSON.parse("\"Hard\"", ResetType) == ResetHard
        @test JSON.parse("\"A\"", ChargingRateUnitType) == ChargingRateA
    end

    @testset "Invalid string throws" begin
        @test_throws KeyError JSON.parse("\"InvalidValue\"", RegistrationStatus)
    end

    @testset "Round-trip: RegistrationStatus" begin
        for val in instances(RegistrationStatus)
            @test JSON.parse(JSON.json(val), RegistrationStatus) == val
        end
    end

    @testset "Round-trip: ChargePointErrorCode" begin
        for val in instances(ChargePointErrorCode)
            @test JSON.parse(JSON.json(val), ChargePointErrorCode) == val
        end
    end

    @testset "Round-trip: Measurand" begin
        for val in instances(Measurand)
            @test JSON.parse(JSON.json(val), Measurand) == val
        end
    end

    @testset "Round-trip: Phase" begin
        for val in instances(Phase)
            @test JSON.parse(JSON.json(val), Phase) == val
        end
    end

    @testset "Round-trip: AvailabilityType" begin
        for val in instances(AvailabilityType)
            @test JSON.parse(JSON.json(val), AvailabilityType) == val
        end
    end

    @testset "Round-trip: Reason" begin
        for val in instances(Reason)
            @test JSON.parse(JSON.json(val), Reason) == val
        end
    end

    @testset "Round-trip: MessageTrigger" begin
        for val in instances(MessageTrigger)
            @test JSON.parse(JSON.json(val), MessageTrigger) == val
        end
    end
end
