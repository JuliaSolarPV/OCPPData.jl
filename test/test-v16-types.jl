@testitem "BootNotificationRequest kwdef construction" tags = [:fast] begin
    using OCPP.V16
    req = BootNotificationRequest(
        charge_point_vendor = "TestVendor",
        charge_point_model = "TestModel",
    )
    @test req.charge_point_vendor == "TestVendor"
    @test req.charge_point_model == "TestModel"
    @test req.firmware_version === nothing
end

@testitem "BootNotificationRequest JSON camelCase output" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = BootNotificationRequest(
        charge_point_vendor = "Vendor",
        charge_point_model = "Model",
    )
    json = JSON.json(req)
    @test occursin("chargePointVendor", json)
    @test occursin("chargePointModel", json)
    @test !occursin("charge_point_vendor", json)
end

@testitem "BootNotificationRequest JSON round-trip" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = BootNotificationRequest(
        charge_point_vendor = "Vendor",
        charge_point_model = "Model",
        firmware_version = "1.0",
    )
    json = JSON.json(req)
    req2 = JSON.parse(json, BootNotificationRequest)
    @test req == req2
end

@testitem "BootNotificationResponse with enum" tags = [:fast] begin
    using OCPP.V16
    using JSON
    resp = BootNotificationResponse(
        status = RegistrationAccepted,
        current_time = "2025-01-01T00:00:00Z",
        interval = 300,
    )
    json = JSON.json(resp)
    @test occursin("\"Accepted\"", json)
    @test occursin("currentTime", json)
    resp2 = JSON.parse(json, BootNotificationResponse)
    @test resp2.status == RegistrationAccepted
    @test resp2.interval == 300
end

@testitem "Empty struct round-trip" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = HeartbeatRequest()
    json = JSON.json(req)
    @test json == "{}"
    req2 = JSON.parse(json, HeartbeatRequest)
    @test req2 isa HeartbeatRequest
end

@testitem "IdTagInfo shared sub-type" tags = [:fast] begin
    using OCPP.V16
    using JSON
    info = IdTagInfo(status = AuthorizationAccepted, expiry_date = "2025-12-31T23:59:59Z")
    json = JSON.json(info)
    @test occursin("expiryDate", json)
    @test occursin("\"Accepted\"", json)
    info2 = JSON.parse(json, IdTagInfo)
    @test info2.status == AuthorizationAccepted
    @test info2.expiry_date == "2025-12-31T23:59:59Z"
end

@testitem "StartTransactionResponse with nested IdTagInfo" tags = [:fast] begin
    using OCPP.V16
    using JSON
    resp = StartTransactionResponse(
        transaction_id = 42,
        id_tag_info = IdTagInfo(status = AuthorizationAccepted),
    )
    json = JSON.json(resp)
    resp2 = JSON.parse(json, StartTransactionResponse)
    @test resp2.transaction_id == 42
    @test resp2.id_tag_info.status == AuthorizationAccepted
end

@testitem "MeterValue with SampledValue" tags = [:fast] begin
    using OCPP.V16
    using JSON
    sv = SampledValue(
        value = "100.5",
        measurand = MeasurandEnergyActiveImportRegister,
        unit = UnitkWh,
    )
    mv = MeterValue(timestamp = "2025-01-01T12:00:00Z", sampled_value = [sv])
    json = JSON.json(mv)
    @test occursin("sampledValue", json)
    @test occursin("Energy.Active.Import.Register", json)
    mv2 = JSON.parse(json, MeterValue)
    @test mv2.sampled_value[1].value == "100.5"
    @test mv2.sampled_value[1].measurand == MeasurandEnergyActiveImportRegister
end

@testitem "ChargingProfile nested struct" tags = [:fast] begin
    using OCPP.V16
    using JSON
    profile = ChargingProfile(
        charging_profile_id = 1,
        stack_level = 0,
        charging_profile_purpose = TxDefaultProfile,
        charging_profile_kind = Absolute,
        charging_schedule = ChargingSchedule(
            charging_rate_unit = ChargingRateW,
            charging_schedule_period = [
                ChargingSchedulePeriod(start_period = 0, limit = 11000.0),
                ChargingSchedulePeriod(start_period = 3600, limit = 7400.0),
            ],
        ),
    )
    json = JSON.json(profile)
    @test occursin("chargingProfileId", json)
    @test occursin("chargingSchedulePeriod", json)
    profile2 = JSON.parse(json, ChargingProfile)
    @test profile2.charging_profile_id == 1
    @test length(profile2.charging_schedule.charging_schedule_period) == 2
    @test profile2.charging_schedule.charging_schedule_period[2].limit == 7400.0
end

@testitem "StopTransactionRequest with optional transaction_data" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = StopTransactionRequest(
        meter_stop = 5000,
        timestamp = "2025-01-01T13:00:00Z",
        transaction_id = 42,
        reason = ReasonLocal,
        transaction_data = [
            MeterValue(
                timestamp = "2025-01-01T13:00:00Z",
                sampled_value = [SampledValue(value = "5000")],
            ),
        ],
    )
    json = JSON.json(req)
    req2 = JSON.parse(json, StopTransactionRequest)
    @test req2.reason == ReasonLocal
    @test req2.transaction_data[1].sampled_value[1].value == "5000"
end

@testitem "StatusNotificationRequest" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = StatusNotificationRequest(
        connector_id = 1,
        error_code = NoError,
        status = ChargePointAvailable,
    )
    json = JSON.json(req)
    @test occursin("\"NoError\"", json)
    @test occursin("\"Available\"", json)
    req2 = JSON.parse(json, StatusNotificationRequest)
    @test req2.error_code == NoError
    @test req2.status == ChargePointAvailable
end

@testitem "AuthorizeRequest JSON round-trip" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = AuthorizeRequest(id_tag = "RFID1234")
    @test req.id_tag == "RFID1234"
    json = JSON.json(req)
    @test occursin("idTag", json)
    req2 = JSON.parse(json, AuthorizeRequest)
    @test req2.id_tag == "RFID1234"
end

@testitem "AuthorizeResponse with nested IdTagInfo" tags = [:fast] begin
    using OCPP.V16
    using JSON
    resp = AuthorizeResponse(id_tag_info = IdTagInfo(status = AuthorizationAccepted))
    json = JSON.json(resp)
    @test occursin("idTagInfo", json)
    resp2 = JSON.parse(json, AuthorizeResponse)
    @test resp2.id_tag_info.status == AuthorizationAccepted
end

@testitem "DataTransferRequest optional fields" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = DataTransferRequest(vendor_id = "com.example", message_id = "msg1", data = "hello")
    json = JSON.json(req)
    @test occursin("vendorId", json)
    req2 = JSON.parse(json, DataTransferRequest)
    @test req2.vendor_id == "com.example"
    @test req2.message_id == "msg1"
    req3 = DataTransferRequest(vendor_id = "com.example")
    @test req3.message_id === nothing
    @test req3.data === nothing
end

@testitem "ChangeConfigurationRequest round-trip" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = ChangeConfigurationRequest(key = "HeartbeatInterval", value = "300")
    json = JSON.json(req)
    @test occursin("HeartbeatInterval", json)
    req2 = JSON.parse(json, ChangeConfigurationRequest)
    @test req2.key == "HeartbeatInterval"
    @test req2.value == "300"
end

@testitem "GetConfigurationRequest with optional key array" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = GetConfigurationRequest(key = ["HeartbeatInterval", "ConnectionTimeOut"])
    json = JSON.json(req)
    @test occursin("HeartbeatInterval", json)
    req2 = JSON.parse(json, GetConfigurationRequest)
    @test req2.key == ["HeartbeatInterval", "ConnectionTimeOut"]
    req3 = GetConfigurationRequest()
    @test req3.key === nothing
end

@testitem "SetChargingProfileRequest camelCase for csChargingProfiles" tags = [:fast] begin
    using OCPP.V16
    using JSON
    req = SetChargingProfileRequest(
        connector_id = 1,
        cs_charging_profiles = ChargingProfile(
            charging_profile_id = 1,
            stack_level = 0,
            charging_profile_purpose = ChargePointMaxProfile,
            charging_profile_kind = Absolute,
            charging_schedule = ChargingSchedule(
                charging_rate_unit = ChargingRateA,
                charging_schedule_period = [
                    ChargingSchedulePeriod(start_period = 0, limit = 32.0),
                ],
            ),
        ),
    )
    json = JSON.json(req)
    @test occursin("csChargingProfiles", json)
    req2 = JSON.parse(json, SetChargingProfileRequest)
    @test req2.cs_charging_profiles.charging_profile_id == 1
end
