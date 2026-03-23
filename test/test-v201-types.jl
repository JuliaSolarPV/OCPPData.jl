@testitem "V201 BootNotificationRequest construction" tags = [:fast] begin
    using OCPP.V201
    req = BootNotificationRequest(
        reason = BootReasonPowerUp,
        charging_station = ChargingStation(model = "TestModel", vendor_name = "TestVendor"),
    )
    @test req.reason == BootReasonPowerUp
    @test req.charging_station.model == "TestModel"
    @test req.custom_data === nothing
end

@testitem "V201 BootNotificationRequest JSON camelCase output" tags = [:fast] begin
    using OCPP.V201
    import JSON
    req = BootNotificationRequest(
        reason = BootReasonPowerUp,
        charging_station = ChargingStation(model = "Model", vendor_name = "Vendor"),
    )
    json = JSON.json(req)
    @test occursin("chargingStation", json)
    @test occursin("vendorName", json)
    @test !occursin("charging_station", json)
    @test !occursin("vendor_name", json)
end

@testitem "V201 BootNotificationRequest JSON round-trip" tags = [:fast] begin
    using OCPP.V201
    import JSON
    req = BootNotificationRequest(
        reason = BootReasonPowerUp,
        charging_station = ChargingStation(model = "TestModel", vendor_name = "TestVendor"),
    )
    json = JSON.json(req)
    req2 = JSON.parse(json, BootNotificationRequest)
    @test req == req2
end

@testitem "V201 BootNotificationResponse with enum" tags = [:fast] begin
    using OCPP.V201
    import JSON
    resp = BootNotificationResponse(
        status = RegistrationAccepted,
        current_time = "2025-01-01T00:00:00Z",
        interval = 300,
    )
    json = JSON.json(resp)
    @test occursin("\"Accepted\"", json)
    resp2 = JSON.parse(json, BootNotificationResponse)
    @test resp2.status == RegistrationAccepted
    @test resp2.interval == 300
end

@testitem "V201 AuthorizeRequest with nested types" tags = [:fast] begin
    using OCPP.V201
    import JSON
    req = AuthorizeRequest(id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral))
    json = JSON.json(req)
    @test occursin("idToken", json)
    req2 = JSON.parse(json, AuthorizeRequest)
    @test req2.id_token.id_token == "RFID1234"
    @test req2.id_token.type == IdTokenCentral
end

@testitem "V201 HeartbeatRequest empty struct round-trip" tags = [:fast] begin
    using OCPP.V201
    import JSON
    req = HeartbeatRequest()
    json = JSON.json(req)
    req2 = JSON.parse(json, HeartbeatRequest)
    @test req2 isa HeartbeatRequest
end

@testitem "V201 TransactionEventRequest" tags = [:fast] begin
    using OCPP.V201
    import JSON
    req = TransactionEventRequest(
        event_type = Started,
        timestamp = "2025-01-01T12:00:00Z",
        trigger_reason = TriggerReasonAuthorized,
        seq_no = 0,
        transaction_info = Transaction(transaction_id = "tx-001"),
    )
    json = JSON.json(req)
    @test occursin("eventType", json)
    @test occursin("\"Started\"", json)
    req2 = JSON.parse(json, TransactionEventRequest)
    @test req2.event_type == Started
    @test req2.transaction_info.transaction_id == "tx-001"
end

@testitem "V201 CustomData extension point" tags = [:fast] begin
    using OCPP.V201
    cd = CustomData(vendor_id = "com.example")
    @test cd.vendor_id == "com.example"
end
