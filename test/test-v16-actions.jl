@testitem "V16 Actions" tags = [:fast] begin
    using OCPP.V16
    using Test

    @testset "request_type lookup" begin
        @test request_type("BootNotification") == BootNotificationRequest
        @test request_type("Heartbeat") == HeartbeatRequest
        @test request_type("StartTransaction") == StartTransactionRequest
    end

    @testset "response_type lookup" begin
        @test response_type("BootNotification") == BootNotificationResponse
        @test response_type("Heartbeat") == HeartbeatResponse
        @test response_type("StartTransaction") == StartTransactionResponse
    end

    @testset "All 28 actions present in registry" begin
        @test length(V16_ACTIONS) == 28
        expected_actions = [
            "Authorize",
            "BootNotification",
            "CancelReservation",
            "ChangeAvailability",
            "ChangeConfiguration",
            "ClearCache",
            "ClearChargingProfile",
            "DataTransfer",
            "DiagnosticsStatusNotification",
            "FirmwareStatusNotification",
            "GetCompositeSchedule",
            "GetConfiguration",
            "GetDiagnostics",
            "GetLocalListVersion",
            "Heartbeat",
            "MeterValues",
            "RemoteStartTransaction",
            "RemoteStopTransaction",
            "ReserveNow",
            "Reset",
            "SendLocalList",
            "SetChargingProfile",
            "StartTransaction",
            "StatusNotification",
            "StopTransaction",
            "TriggerMessage",
            "UnlockConnector",
            "UpdateFirmware",
        ]
        for action in expected_actions
            @test haskey(V16_ACTIONS, action)
        end
    end

    @testset "Unknown action throws ArgumentError" begin
        @test_throws ArgumentError request_type("FakeAction")
        @test_throws ArgumentError response_type("FakeAction")
    end

    @testset "Registry types are concrete" begin
        for (action, types) in V16_ACTIONS
            @test isconcretetype(types.request)
            @test isconcretetype(types.response)
        end
    end
end
