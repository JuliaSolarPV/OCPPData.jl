@testitem "Enum string() produces OCPP value" tags = [:fast] begin
    using OCPP.V16
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

@testitem "Enum JSON write" tags = [:fast] begin
    using OCPP.V16
    using JSON
    @test JSON.json(RegistrationAccepted) == "\"Accepted\""
    @test JSON.json(ResetHard) == "\"Hard\""
    @test JSON.json(ChargingRateA) == "\"A\""
    @test JSON.json(MeasurandEnergyActiveImportRegister) ==
          "\"Energy.Active.Import.Register\""
end

@testitem "Enum JSON read" tags = [:fast] begin
    using OCPP.V16
    using JSON
    @test JSON.parse("\"Accepted\"", RegistrationStatus) == RegistrationAccepted
    @test JSON.parse("\"Pending\"", RegistrationStatus) == RegistrationPending
    @test JSON.parse("\"Hard\"", ResetType) == ResetHard
    @test JSON.parse("\"A\"", ChargingRateUnitType) == ChargingRateA
end

@testitem "Enum round-trip for all RegistrationStatus values" tags = [:fast] begin
    using OCPP.V16
    using JSON
    for val in instances(RegistrationStatus)
        @test JSON.parse(JSON.json(val), RegistrationStatus) == val
    end
end

@testitem "Enum round-trip for ChargePointErrorCode" tags = [:fast] begin
    using OCPP.V16
    using JSON
    for val in instances(ChargePointErrorCode)
        @test JSON.parse(JSON.json(val), ChargePointErrorCode) == val
    end
end

@testitem "Enum round-trip for Measurand" tags = [:fast] begin
    using OCPP.V16
    using JSON
    for val in instances(Measurand)
        @test JSON.parse(JSON.json(val), Measurand) == val
    end
end

@testitem "Enum round-trip for Phase" tags = [:fast] begin
    using OCPP.V16
    using JSON
    for val in instances(Phase)
        @test JSON.parse(JSON.json(val), Phase) == val
    end
end

@testitem "Enum invalid string throws" tags = [:fast] begin
    using OCPP.V16
    using JSON
    @test_throws KeyError JSON.parse("\"InvalidValue\"", RegistrationStatus)
end
