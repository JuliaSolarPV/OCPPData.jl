@testitem "V201 Actions" tags = [:fast] begin
    using OCPPData.V201
    using Test

    @testset "request_type lookup" begin
        @test request_type("BootNotification") == BootNotificationRequest
        @test request_type("Heartbeat") == HeartbeatRequest
        @test request_type("TransactionEvent") == TransactionEventRequest
    end

    @testset "response_type lookup" begin
        @test response_type("BootNotification") == BootNotificationResponse
        @test response_type("Heartbeat") == HeartbeatResponse
        @test response_type("Authorize") == AuthorizeResponse
    end

    @testset "All 64 actions present in registry" begin
        @test length(V201_ACTIONS) == 64
        for action in [
            "Authorize",
            "BootNotification",
            "CancelReservation",
            "ClearCache",
            "DataTransfer",
            "GetVariables",
            "Heartbeat",
            "RequestStartTransaction",
            "RequestStopTransaction",
            "Reset",
            "SetVariables",
            "TransactionEvent",
            "UnlockConnector",
            "UpdateFirmware",
        ]
            @test haskey(V201_ACTIONS, action)
        end
    end

    @testset "Unknown action throws ArgumentError" begin
        @test_throws ArgumentError request_type("NonExistentAction")
        @test_throws ArgumentError response_type("NonExistentAction")
    end

    @testset "Registry types are concrete" begin
        for (action, types) in V201_ACTIONS
            @test isconcretetype(types.request)
            @test isconcretetype(types.response)
        end
    end
end
