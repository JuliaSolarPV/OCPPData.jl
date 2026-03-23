@testitem "V201 Enums" tags = [:fast] begin
    using OCPP.V201
    import JSON
    using Test

    @testset "string() produces OCPP value" begin
        @test string(BootReasonPowerUp) == "PowerUp"
        @test string(BootReasonWatchdog) == "Watchdog"
        @test string(RegistrationAccepted) == "Accepted"
        @test string(RegistrationPending) == "Pending"
        @test string(GenericAccepted) == "Accepted"
        @test string(GenericRejected) == "Rejected"
        @test string(Immediate) == "Immediate"
        @test string(OnIdle) == "OnIdle"
    end

    @testset "JSON write" begin
        @test JSON.json(BootReasonPowerUp) == "\"PowerUp\""
        @test JSON.json(RegistrationAccepted) == "\"Accepted\""
        @test JSON.json(A) == "\"A\""
    end

    @testset "JSON read" begin
        @test JSON.parse("\"PowerUp\"", BootReason) == BootReasonPowerUp
        @test JSON.parse("\"Accepted\"", RegistrationStatus) == RegistrationAccepted
        @test JSON.parse("\"Immediate\"", Reset) == Immediate
    end

    @testset "Invalid string throws" begin
        @test_throws KeyError JSON.parse("\"InvalidValue\"", RegistrationStatus)
    end

    @testset "Round-trip: BootReason" begin
        for val in instances(BootReason)
            @test JSON.parse(JSON.json(val), BootReason) == val
        end
    end

    @testset "Round-trip: ConnectorStatus" begin
        for val in instances(ConnectorStatus)
            @test JSON.parse(JSON.json(val), ConnectorStatus) == val
        end
    end

    @testset "Round-trip: Measurand" begin
        for val in instances(Measurand)
            @test JSON.parse(JSON.json(val), Measurand) == val
        end
    end

    @testset "Round-trip: Reset" begin
        for val in instances(Reset)
            @test JSON.parse(JSON.json(val), Reset) == val
        end
    end

    @testset "Round-trip: TriggerReason" begin
        for val in instances(TriggerReason)
            @test JSON.parse(JSON.json(val), TriggerReason) == val
        end
    end
end
