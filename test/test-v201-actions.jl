@testitem "V201 request_type lookup" tags = [:fast] begin
    using OCPP.V201
    @test request_type("BootNotification") == BootNotificationRequest
    @test request_type("Heartbeat") == HeartbeatRequest
    @test request_type("TransactionEvent") == TransactionEventRequest
end

@testitem "V201 response_type lookup" tags = [:fast] begin
    using OCPP.V201
    @test response_type("BootNotification") == BootNotificationResponse
    @test response_type("Heartbeat") == HeartbeatResponse
    @test response_type("Authorize") == AuthorizeResponse
end

@testitem "V201 all 64 actions present in registry" tags = [:fast] begin
    using OCPP.V201
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

@testitem "V201 unknown action throws ArgumentError" tags = [:fast] begin
    using OCPP.V201
    @test_throws ArgumentError request_type("NonExistentAction")
    @test_throws ArgumentError response_type("NonExistentAction")
end

@testitem "V201 registry types are concrete" tags = [:fast] begin
    using OCPP.V201
    for (action, types) in V201_ACTIONS
        @test isconcretetype(types.request)
        @test isconcretetype(types.response)
    end
end
