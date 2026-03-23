@testitem "V201 Types" tags = [:fast] begin
    using OCPP.V201
    import JSON
    using Test

    @testset "BootNotificationRequest construction" begin
        req = BootNotificationRequest(
            reason = BootReasonPowerUp,
            charging_station = ChargingStation(
                model = "TestModel",
                vendor_name = "TestVendor",
            ),
        )
        @test req.reason == BootReasonPowerUp
        @test req.charging_station.model == "TestModel"
        @test req.custom_data === nothing
    end

    @testset "BootNotificationRequest JSON camelCase output" begin
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

    @testset "BootNotificationRequest JSON round-trip" begin
        req = BootNotificationRequest(
            reason = BootReasonPowerUp,
            charging_station = ChargingStation(
                model = "TestModel",
                vendor_name = "TestVendor",
            ),
        )
        req2 = JSON.parse(JSON.json(req), BootNotificationRequest)
        @test req == req2
    end

    @testset "BootNotificationResponse with enum" begin
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

    @testset "AuthorizeRequest with nested IdToken" begin
        req = AuthorizeRequest(
            id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
        )
        json = JSON.json(req)
        @test occursin("idToken", json)
        req2 = JSON.parse(json, AuthorizeRequest)
        @test req2.id_token.id_token == "RFID1234"
        @test req2.id_token.type == IdTokenCentral
    end

    @testset "HeartbeatRequest empty struct round-trip" begin
        req = HeartbeatRequest()
        req2 = JSON.parse(JSON.json(req), HeartbeatRequest)
        @test req2 isa HeartbeatRequest
    end

    @testset "TransactionEventRequest" begin
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

    @testset "CustomData extension point" begin
        cd = CustomData(vendor_id = "com.example")
        @test cd.vendor_id == "com.example"
    end

    @testset "StatusNotificationRequest construction and JSON" begin
        status_val = first(instances(ConnectorStatus))
        req = StatusNotificationRequest(
            timestamp = "2025-01-01T12:00:00Z",
            connector_status = status_val,
            evse_id = 1,
            connector_id = 1,
        )
        json = JSON.json(req)
        @test occursin("connectorStatus", json)
        @test occursin("evseId", json)
        req2 = JSON.parse(json, StatusNotificationRequest)
        @test req2.evse_id == 1
        @test req2.connector_id == 1
        @test req2.connector_status == status_val
    end

    @testset "GetVariablesRequest with nested Component and Variable" begin
        req = GetVariablesRequest(
            get_variable_data = [
                GetVariableData(
                    component = Component(name = "SmartChargingCtrlr"),
                    variable = Variable(name = "Enabled"),
                ),
            ],
        )
        json = JSON.json(req)
        @test occursin("getVariableData", json)
        @test occursin("SmartChargingCtrlr", json)
        req2 = JSON.parse(json, GetVariablesRequest)
        @test req2.get_variable_data[1].component.name == "SmartChargingCtrlr"
        @test req2.get_variable_data[1].variable.name == "Enabled"
    end

    @testset "DataTransferRequest optional fields" begin
        req = DataTransferRequest(vendor_id = "com.example", message_id = "Ping")
        json = JSON.json(req)
        @test occursin("vendorId", json)
        req2 = JSON.parse(json, DataTransferRequest)
        @test req2.vendor_id == "com.example"
        @test req2.message_id == "Ping"
        req3 = DataTransferRequest(vendor_id = "com.example")
        @test req3.message_id === nothing
    end

    @testset "ResetRequest round-trip" begin
        req = ResetRequest(type = Immediate)
        json = JSON.json(req)
        @test occursin("\"Immediate\"", json)
        req2 = JSON.parse(json, ResetRequest)
        @test req2.type == Immediate
    end
end
