@testitem "V201 enum string() produces OCPP value" tags = [:fast] begin
    using OCPP.V201
    @test string(BootReasonPowerUp) == "PowerUp"
    @test string(BootReasonWatchdog) == "Watchdog"
    @test string(RegistrationAccepted) == "Accepted"
    @test string(RegistrationPending) == "Pending"
    @test string(GenericAccepted) == "Accepted"
    @test string(GenericRejected) == "Rejected"
    @test string(Immediate) == "Immediate"
    @test string(OnIdle) == "OnIdle"
end

@testitem "V201 enum JSON3 write" tags = [:fast] begin
    using OCPP.V201
    import JSON
    @test JSON.json(BootReasonPowerUp) == "\"PowerUp\""
    @test JSON.json(RegistrationAccepted) == "\"Accepted\""
    @test JSON.json(A) == "\"A\""
end

@testitem "V201 enum JSON3 read" tags = [:fast] begin
    using OCPP.V201
    import JSON
    @test JSON.parse("\"PowerUp\"", BootReason) == BootReasonPowerUp
    @test JSON.parse("\"Accepted\"", RegistrationStatus) == RegistrationAccepted
    @test JSON.parse("\"Immediate\"", Reset) == Immediate
end

@testitem "V201 enum round-trip for BootReason" tags = [:fast] begin
    using OCPP.V201
    import JSON
    for val in instances(BootReason)
        @test JSON.parse(JSON.json(val), BootReason) == val
    end
end

@testitem "V201 enum round-trip for ConnectorStatus" tags = [:fast] begin
    using OCPP.V201
    import JSON
    for val in instances(ConnectorStatus)
        @test JSON.parse(JSON.json(val), ConnectorStatus) == val
    end
end

@testitem "V201 enum round-trip for Measurand" tags = [:fast] begin
    using OCPP.V201
    import JSON
    for val in instances(Measurand)
        @test JSON.parse(JSON.json(val), Measurand) == val
    end
end

@testitem "V201 enum invalid string throws" tags = [:fast] begin
    using OCPP.V201
    import JSON
    @test_throws KeyError JSON.parse("\"InvalidValue\"", RegistrationStatus)
end

@testitem "V201 enum round-trip for Reset" tags = [:fast] begin
    using OCPP.V201
    import JSON
    for val in instances(Reset)
        @test JSON.parse(JSON.json(val), Reset) == val
    end
end

@testitem "V201 enum round-trip for TriggerReason" tags = [:fast] begin
    using OCPP.V201
    import JSON
    for val in instances(TriggerReason)
        @test JSON.parse(JSON.json(val), TriggerReason) == val
    end
end
