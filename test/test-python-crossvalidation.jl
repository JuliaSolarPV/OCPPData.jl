# Cross-validation tests: serialize Julia types to JSON, validate with Python ocpp library
# via PythonCall.jl + CondaPkg.jl.
#
# Run:
#   julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->(:crossvalidation in ti.tags) verbose=true'

@testsnippet PythonOCPP begin
    import JSON
    using CondaPkg
    CondaPkg.add_pip("ocpp"; version = ">=2.0.0")
    using PythonCall

    const _ocpp_messages = pyimport("ocpp.messages")
    const _pyjson = pyimport("json")
    const _PyCall = _ocpp_messages.Call
    const _PyCallResult = _ocpp_messages.CallResult
    const _validate = _ocpp_messages._validate_payload

    # Recursively remove nothing/null values so optional absent fields
    # don't appear as null in the payload (OCPP schemas disallow null).
    function _strip_nulls!(d::AbstractDict)
        for k in collect(keys(d))
            v = d[k]
            if v === nothing
                delete!(d, k)
            elseif v isa AbstractDict
                _strip_nulls!(v)
            elseif v isa Vector
                for item in v
                    item isa AbstractDict && _strip_nulls!(item)
                end
            end
        end
        return d
    end

    function _to_pydict(julia_struct)
        d = JSON.parse(JSON.json(julia_struct))
        _strip_nulls!(d)
        return _pyjson.loads(JSON.json(d))
    end

    """Validate a Julia struct as an OCPP request payload."""
    function py_validate_request(action::String, version::String, julia_struct)
        msg = _PyCall(unique_id = "1", action = action, payload = _to_pydict(julia_struct))
        _validate(msg; ocpp_version = version)
    end

    """Validate a Julia struct as an OCPP response payload."""
    function py_validate_response(action::String, version::String, julia_struct)
        msg = _PyCallResult(
            unique_id = "1",
            action = action,
            payload = _to_pydict(julia_struct),
        )
        _validate(msg; ocpp_version = version)
    end
end

# ===========================================================================
# V16 — Charge Point → Central System (client-initiated)
# ===========================================================================

@testitem "Python cross-validation: V16 client → CSMS" tags = [:crossvalidation] setup =
    [PythonOCPP] begin
    using OCPP.V16
    using Test

    @testset "BootNotification req+resp" begin
        py_validate_request(
            "BootNotification",
            "1.6",
            BootNotificationRequest(
                charge_point_vendor = "TestVendor",
                charge_point_model = "TestModel",
                firmware_version = "1.0.0",
            ),
        )
        py_validate_response(
            "BootNotification",
            "1.6",
            BootNotificationResponse(
                status = RegistrationAccepted,
                current_time = "2025-01-01T00:00:00Z",
                interval = 300,
            ),
        )
        @test true
    end

    @testset "Heartbeat req+resp" begin
        py_validate_request("Heartbeat", "1.6", HeartbeatRequest())
        py_validate_response(
            "Heartbeat",
            "1.6",
            HeartbeatResponse(current_time = "2025-01-01T00:00:00Z"),
        )
        @test true
    end

    @testset "Authorize req+resp" begin
        py_validate_request("Authorize", "1.6", AuthorizeRequest(id_tag = "RFID1234"))
        py_validate_response(
            "Authorize",
            "1.6",
            AuthorizeResponse(id_tag_info = IdTagInfo(status = AuthorizationAccepted)),
        )
        @test true
    end

    @testset "StartTransaction req+resp" begin
        py_validate_request(
            "StartTransaction",
            "1.6",
            StartTransactionRequest(
                connector_id = 1,
                id_tag = "RFID1234",
                meter_start = 0,
                timestamp = "2025-01-01T12:00:00Z",
            ),
        )
        py_validate_response(
            "StartTransaction",
            "1.6",
            StartTransactionResponse(
                transaction_id = 42,
                id_tag_info = IdTagInfo(status = AuthorizationAccepted),
            ),
        )
        @test true
    end

    @testset "StopTransaction req+resp" begin
        py_validate_request(
            "StopTransaction",
            "1.6",
            StopTransactionRequest(
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
            ),
        )
        py_validate_response(
            "StopTransaction",
            "1.6",
            StopTransactionResponse(
                id_tag_info = IdTagInfo(status = AuthorizationAccepted),
            ),
        )
        @test true
    end

    @testset "StatusNotification req+resp" begin
        py_validate_request(
            "StatusNotification",
            "1.6",
            StatusNotificationRequest(
                connector_id = 1,
                error_code = NoError,
                status = ChargePointAvailable,
            ),
        )
        py_validate_response("StatusNotification", "1.6", StatusNotificationResponse())
        @test true
    end

    @testset "MeterValues req+resp" begin
        py_validate_request(
            "MeterValues",
            "1.6",
            MeterValuesRequest(
                connector_id = 1,
                meter_value = [
                    MeterValue(
                        timestamp = "2025-01-01T12:00:00Z",
                        sampled_value = [
                            SampledValue(
                                value = "100.5",
                                measurand = MeasurandEnergyActiveImportRegister,
                                unit = UnitkWh,
                            ),
                        ],
                    ),
                ],
            ),
        )
        py_validate_response("MeterValues", "1.6", MeterValuesResponse())
        @test true
    end

    @testset "DiagnosticsStatusNotification req+resp" begin
        py_validate_request(
            "DiagnosticsStatusNotification",
            "1.6",
            DiagnosticsStatusNotificationRequest(status = DiagnosticsUploaded),
        )
        py_validate_response(
            "DiagnosticsStatusNotification",
            "1.6",
            DiagnosticsStatusNotificationResponse(),
        )
        @test true
    end

    @testset "FirmwareStatusNotification req+resp" begin
        py_validate_request(
            "FirmwareStatusNotification",
            "1.6",
            FirmwareStatusNotificationRequest(status = FirmwareInstalled),
        )
        py_validate_response(
            "FirmwareStatusNotification",
            "1.6",
            FirmwareStatusNotificationResponse(),
        )
        @test true
    end

    @testset "DataTransfer req+resp (bidirectional)" begin
        py_validate_request(
            "DataTransfer",
            "1.6",
            DataTransferRequest(
                vendor_id = "com.example",
                message_id = "TestMsg",
                data = "{\"key\": \"value\"}",
            ),
        )
        py_validate_response(
            "DataTransfer",
            "1.6",
            DataTransferResponse(status = DataTransferAccepted, data = "response-data"),
        )
        @test true
    end
end

# ===========================================================================
# V16 — Central System → Charge Point (management-initiated)
# ===========================================================================

@testitem "Python cross-validation: V16 CSMS → client" tags = [:crossvalidation] setup =
    [PythonOCPP] begin
    using OCPP.V16
    using Test

    @testset "ChangeAvailability req+resp" begin
        py_validate_request(
            "ChangeAvailability",
            "1.6",
            ChangeAvailabilityRequest(connector_id = 1, type = Operative),
        )
        py_validate_response(
            "ChangeAvailability",
            "1.6",
            ChangeAvailabilityResponse(status = AvailabilityAccepted),
        )
        @test true
    end

    @testset "ChangeConfiguration req+resp" begin
        py_validate_request(
            "ChangeConfiguration",
            "1.6",
            ChangeConfigurationRequest(key = "HeartbeatInterval", value = "300"),
        )
        py_validate_response(
            "ChangeConfiguration",
            "1.6",
            ChangeConfigurationResponse(status = ConfigurationAccepted),
        )
        @test true
    end

    @testset "ClearCache req+resp" begin
        py_validate_request("ClearCache", "1.6", ClearCacheRequest())
        py_validate_response(
            "ClearCache",
            "1.6",
            ClearCacheResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "ClearChargingProfile req+resp" begin
        py_validate_request(
            "ClearChargingProfile",
            "1.6",
            ClearChargingProfileRequest(
                id = 1,
                connector_id = 0,
                charging_profile_purpose = TxDefaultProfile,
            ),
        )
        py_validate_response(
            "ClearChargingProfile",
            "1.6",
            ClearChargingProfileResponse(status = ClearChargingProfileAccepted),
        )
        @test true
    end

    @testset "GetConfiguration req+resp" begin
        py_validate_request(
            "GetConfiguration",
            "1.6",
            GetConfigurationRequest(key = ["HeartbeatInterval", "ConnectionTimeOut"]),
        )
        py_validate_response(
            "GetConfiguration",
            "1.6",
            GetConfigurationResponse(
                configuration_key = [
                    KeyValueType(key = "HeartbeatInterval", readonly = false, value = "300"),
                ],
                unknown_key = ["NonExistentKey"],
            ),
        )
        @test true
    end

    @testset "GetLocalListVersion req+resp" begin
        py_validate_request("GetLocalListVersion", "1.6", GetLocalListVersionRequest())
        py_validate_response(
            "GetLocalListVersion",
            "1.6",
            GetLocalListVersionResponse(list_version = 5),
        )
        @test true
    end

    @testset "RemoteStartTransaction req+resp" begin
        py_validate_request(
            "RemoteStartTransaction",
            "1.6",
            RemoteStartTransactionRequest(id_tag = "RFID1234", connector_id = 1),
        )
        py_validate_response(
            "RemoteStartTransaction",
            "1.6",
            RemoteStartTransactionResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "RemoteStopTransaction req+resp" begin
        py_validate_request(
            "RemoteStopTransaction",
            "1.6",
            RemoteStopTransactionRequest(transaction_id = 42),
        )
        py_validate_response(
            "RemoteStopTransaction",
            "1.6",
            RemoteStopTransactionResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "Reset req+resp" begin
        py_validate_request("Reset", "1.6", ResetRequest(type = ResetHard))
        py_validate_response("Reset", "1.6", ResetResponse(status = GenericAccepted))
        @test true
    end

    @testset "UnlockConnector req+resp" begin
        py_validate_request(
            "UnlockConnector",
            "1.6",
            UnlockConnectorRequest(connector_id = 1),
        )
        py_validate_response(
            "UnlockConnector",
            "1.6",
            UnlockConnectorResponse(status = Unlocked),
        )
        @test true
    end

    @testset "SetChargingProfile req+resp" begin
        py_validate_request(
            "SetChargingProfile",
            "1.6",
            SetChargingProfileRequest(
                connector_id = 1,
                cs_charging_profiles = ChargingProfile(
                    charging_profile_id = 1,
                    stack_level = 0,
                    charging_profile_purpose = TxProfile,
                    charging_profile_kind = Relative,
                    charging_schedule = ChargingSchedule(
                        charging_rate_unit = ChargingRateA,
                        charging_schedule_period = [
                            ChargingSchedulePeriod(start_period = 0, limit = 21.4),
                        ],
                    ),
                    transaction_id = 123456789,
                ),
            ),
        )
        py_validate_response(
            "SetChargingProfile",
            "1.6",
            SetChargingProfileResponse(status = ChargingProfileAccepted),
        )
        @test true
    end

    @testset "GetCompositeSchedule req+resp" begin
        py_validate_request(
            "GetCompositeSchedule",
            "1.6",
            GetCompositeScheduleRequest(
                connector_id = 1,
                duration = 3600,
                charging_rate_unit = ChargingRateW,
            ),
        )
        py_validate_response(
            "GetCompositeSchedule",
            "1.6",
            GetCompositeScheduleResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "CancelReservation req+resp" begin
        py_validate_request(
            "CancelReservation",
            "1.6",
            CancelReservationRequest(reservation_id = 1),
        )
        py_validate_response(
            "CancelReservation",
            "1.6",
            CancelReservationResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "ReserveNow req+resp" begin
        py_validate_request(
            "ReserveNow",
            "1.6",
            ReserveNowRequest(
                connector_id = 1,
                expiry_date = "2025-12-31T23:59:59Z",
                id_tag = "RFID1234",
                reservation_id = 1,
            ),
        )
        py_validate_response(
            "ReserveNow",
            "1.6",
            ReserveNowResponse(status = ReservationAccepted),
        )
        @test true
    end

    @testset "SendLocalList req+resp" begin
        py_validate_request(
            "SendLocalList",
            "1.6",
            SendLocalListRequest(
                list_version = 2,
                update_type = Full,
                local_authorization_list = [
                    AuthorizationData(
                        id_tag = "RFID1234",
                        id_tag_info = IdTagInfo(status = AuthorizationAccepted),
                    ),
                ],
            ),
        )
        py_validate_response(
            "SendLocalList",
            "1.6",
            SendLocalListResponse(status = UpdateAccepted),
        )
        @test true
    end

    @testset "TriggerMessage req+resp" begin
        py_validate_request(
            "TriggerMessage",
            "1.6",
            TriggerMessageRequest(
                requested_message = TriggerBootNotification,
                connector_id = 1,
            ),
        )
        py_validate_response(
            "TriggerMessage",
            "1.6",
            TriggerMessageResponse(status = TriggerMessageAccepted),
        )
        @test true
    end

    @testset "UpdateFirmware req+resp" begin
        py_validate_request(
            "UpdateFirmware",
            "1.6",
            UpdateFirmwareRequest(
                location = "https://firmware.example.com/fw-1.0.bin",
                retrieve_date = "2025-06-01T00:00:00Z",
                retries = 3,
                retry_interval = 60,
            ),
        )
        py_validate_response("UpdateFirmware", "1.6", UpdateFirmwareResponse())
        @test true
    end

    @testset "GetDiagnostics req+resp" begin
        py_validate_request(
            "GetDiagnostics",
            "1.6",
            GetDiagnosticsRequest(
                location = "ftp://diag.example.com/uploads",
                retries = 3,
                retry_interval = 60,
                start_time = "2025-01-01T00:00:00Z",
                stop_time = "2025-01-02T00:00:00Z",
            ),
        )
        py_validate_response(
            "GetDiagnostics",
            "1.6",
            GetDiagnosticsResponse(file_name = "diagnostics-20250101.zip"),
        )
        @test true
    end
end

# ===========================================================================
# V201 — Charging Station → CSMS (client-initiated)
# ===========================================================================

@testitem "Python cross-validation: V201 client → CSMS" tags = [:crossvalidation] setup =
    [PythonOCPP] begin
    using OCPP.V201
    using Test

    @testset "BootNotification req+resp" begin
        py_validate_request(
            "BootNotification",
            "2.0.1",
            BootNotificationRequest(
                reason = BootReasonPowerUp,
                charging_station = ChargingStation(
                    model = "TestModel",
                    vendor_name = "TestVendor",
                ),
            ),
        )
        py_validate_response(
            "BootNotification",
            "2.0.1",
            BootNotificationResponse(
                status = RegistrationAccepted,
                current_time = "2025-01-01T00:00:00Z",
                interval = 300,
            ),
        )
        @test true
    end

    @testset "Heartbeat req+resp" begin
        py_validate_request("Heartbeat", "2.0.1", HeartbeatRequest())
        py_validate_response(
            "Heartbeat",
            "2.0.1",
            HeartbeatResponse(current_time = "2025-01-01T00:00:00Z"),
        )
        @test true
    end

    @testset "Authorize req+resp" begin
        py_validate_request(
            "Authorize",
            "2.0.1",
            AuthorizeRequest(
                id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
            ),
        )
        py_validate_response(
            "Authorize",
            "2.0.1",
            AuthorizeResponse(
                id_token_info = IdTokenInfo(status = AuthorizationAccepted),
            ),
        )
        @test true
    end

    @testset "TransactionEvent req+resp" begin
        py_validate_request(
            "TransactionEvent",
            "2.0.1",
            TransactionEventRequest(
                event_type = Started,
                timestamp = "2025-01-01T12:00:00Z",
                trigger_reason = TriggerReasonAuthorized,
                seq_no = 0,
                transaction_info = Transaction(transaction_id = "tx-001"),
            ),
        )
        py_validate_response("TransactionEvent", "2.0.1", TransactionEventResponse())
        @test true
    end

    @testset "StatusNotification req+resp" begin
        py_validate_request(
            "StatusNotification",
            "2.0.1",
            StatusNotificationRequest(
                timestamp = "2025-01-01T12:00:00Z",
                connector_status = ConnectorAvailable,
                evse_id = 1,
                connector_id = 1,
            ),
        )
        py_validate_response("StatusNotification", "2.0.1", StatusNotificationResponse())
        @test true
    end

    @testset "MeterValues req+resp" begin
        py_validate_request(
            "MeterValues",
            "2.0.1",
            MeterValuesRequest(
                evse_id = 1,
                meter_value = [
                    MeterValue(
                        timestamp = "2025-01-01T12:00:00Z",
                        sampled_value = [SampledValue(value = 100.5)],
                    ),
                ],
            ),
        )
        py_validate_response("MeterValues", "2.0.1", MeterValuesResponse())
        @test true
    end

    @testset "FirmwareStatusNotification req+resp" begin
        py_validate_request(
            "FirmwareStatusNotification",
            "2.0.1",
            FirmwareStatusNotificationRequest(status = FirmwareInstalled),
        )
        py_validate_response(
            "FirmwareStatusNotification",
            "2.0.1",
            FirmwareStatusNotificationResponse(),
        )
        @test true
    end

    @testset "SecurityEventNotification req+resp" begin
        py_validate_request(
            "SecurityEventNotification",
            "2.0.1",
            SecurityEventNotificationRequest(
                type = "FirmwareUpdated",
                timestamp = "2025-01-01T12:00:00Z",
                tech_info = "Firmware updated to v2.0",
            ),
        )
        py_validate_response(
            "SecurityEventNotification",
            "2.0.1",
            SecurityEventNotificationResponse(),
        )
        @test true
    end

    @testset "NotifyEvent req+resp" begin
        py_validate_request(
            "NotifyEvent",
            "2.0.1",
            NotifyEventRequest(
                generated_at = "2025-01-01T12:00:00Z",
                seq_no = 0,
                event_data = [
                    EventData(
                        event_id = 1,
                        timestamp = "2025-01-01T12:00:00Z",
                        trigger = EventTriggerAlerting,
                        actual_value = "true",
                        event_notification_type = HardWiredNotification,
                        component = Component(name = "Connector"),
                        variable = Variable(name = "Available"),
                    ),
                ],
            ),
        )
        py_validate_response("NotifyEvent", "2.0.1", NotifyEventResponse())
        @test true
    end

    @testset "SignCertificate req+resp" begin
        py_validate_request(
            "SignCertificate",
            "2.0.1",
            SignCertificateRequest(
                csr = "-----BEGIN CERTIFICATE REQUEST-----\nMIICYDCC...\n-----END CERTIFICATE REQUEST-----",
                certificate_type = ChargingStationCertificate,
            ),
        )
        py_validate_response(
            "SignCertificate",
            "2.0.1",
            SignCertificateResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "DataTransfer req+resp (bidirectional)" begin
        py_validate_request(
            "DataTransfer",
            "2.0.1",
            DataTransferRequest(
                vendor_id = "com.example",
                message_id = "TestMsg",
                data = "payload-data",
            ),
        )
        py_validate_response(
            "DataTransfer",
            "2.0.1",
            DataTransferResponse(status = DataTransferAccepted),
        )
        @test true
    end
end

# ===========================================================================
# V201 — CSMS → Charging Station (management-initiated)
# ===========================================================================

@testitem "Python cross-validation: V201 CSMS → client" tags = [:crossvalidation] setup =
    [PythonOCPP] begin
    using OCPP.V201
    using Test

    @testset "Reset req+resp" begin
        py_validate_request("Reset", "2.0.1", ResetRequest(type = Immediate))
        py_validate_response(
            "Reset",
            "2.0.1",
            ResetResponse(status = ResetAccepted),
        )
        @test true
    end

    @testset "ChangeAvailability req+resp" begin
        py_validate_request(
            "ChangeAvailability",
            "2.0.1",
            ChangeAvailabilityRequest(
                operational_status = Operative,
                evse = EVSE(id = 1, connector_id = 1),
            ),
        )
        py_validate_response(
            "ChangeAvailability",
            "2.0.1",
            ChangeAvailabilityResponse(status = ChangeAvailabilityAccepted),
        )
        @test true
    end

    @testset "ClearCache req+resp" begin
        py_validate_request("ClearCache", "2.0.1", ClearCacheRequest())
        py_validate_response(
            "ClearCache",
            "2.0.1",
            ClearCacheResponse(status = ClearCacheAccepted),
        )
        @test true
    end

    @testset "ClearChargingProfile req+resp" begin
        py_validate_request(
            "ClearChargingProfile",
            "2.0.1",
            ClearChargingProfileRequest(charging_profile_id = 1),
        )
        py_validate_response(
            "ClearChargingProfile",
            "2.0.1",
            ClearChargingProfileResponse(status = ClearChargingProfileAccepted),
        )
        @test true
    end

    @testset "GetVariables req+resp" begin
        py_validate_request(
            "GetVariables",
            "2.0.1",
            GetVariablesRequest(
                get_variable_data = [
                    GetVariableData(
                        component = Component(name = "SmartChargingCtrlr"),
                        variable = Variable(name = "Enabled"),
                    ),
                ],
            ),
        )
        py_validate_response(
            "GetVariables",
            "2.0.1",
            GetVariablesResponse(
                get_variable_result = [
                    GetVariableResult(
                        attribute_status = GetVariableAccepted,
                        component = Component(name = "SmartChargingCtrlr"),
                        variable = Variable(name = "Enabled"),
                        attribute_value = "true",
                    ),
                ],
            ),
        )
        @test true
    end

    @testset "SetVariables req+resp" begin
        py_validate_request(
            "SetVariables",
            "2.0.1",
            SetVariablesRequest(
                set_variable_data = [
                    SetVariableData(
                        attribute_value = "300",
                        component = Component(name = "ClockCtrlr"),
                        variable = Variable(name = "HeartbeatInterval"),
                    ),
                ],
            ),
        )
        py_validate_response(
            "SetVariables",
            "2.0.1",
            SetVariablesResponse(
                set_variable_result = [
                    SetVariableResult(
                        attribute_status = SetVariableAccepted,
                        component = Component(name = "ClockCtrlr"),
                        variable = Variable(name = "HeartbeatInterval"),
                    ),
                ],
            ),
        )
        @test true
    end

    @testset "UnlockConnector req+resp" begin
        py_validate_request(
            "UnlockConnector",
            "2.0.1",
            UnlockConnectorRequest(evse_id = 1, connector_id = 1),
        )
        py_validate_response(
            "UnlockConnector",
            "2.0.1",
            UnlockConnectorResponse(status = Unlocked),
        )
        @test true
    end

    @testset "GetLocalListVersion req+resp" begin
        py_validate_request("GetLocalListVersion", "2.0.1", GetLocalListVersionRequest())
        py_validate_response(
            "GetLocalListVersion",
            "2.0.1",
            GetLocalListVersionResponse(version_number = 5),
        )
        @test true
    end

    @testset "SendLocalList req+resp" begin
        py_validate_request(
            "SendLocalList",
            "2.0.1",
            SendLocalListRequest(
                version_number = 2,
                update_type = Full,
                local_authorization_list = [
                    AuthorizationData(
                        id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
                        id_token_info = IdTokenInfo(status = AuthorizationAccepted),
                    ),
                ],
            ),
        )
        py_validate_response(
            "SendLocalList",
            "2.0.1",
            SendLocalListResponse(status = SendLocalListAccepted),
        )
        @test true
    end

    @testset "CancelReservation req+resp" begin
        py_validate_request(
            "CancelReservation",
            "2.0.1",
            CancelReservationRequest(reservation_id = 1),
        )
        py_validate_response(
            "CancelReservation",
            "2.0.1",
            CancelReservationResponse(status = CancelReservationAccepted),
        )
        @test true
    end

    @testset "ReserveNow req+resp" begin
        py_validate_request(
            "ReserveNow",
            "2.0.1",
            ReserveNowRequest(
                id = 1,
                expiry_date_time = "2025-12-31T23:59:59Z",
                id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
                evse_id = 1,
            ),
        )
        py_validate_response(
            "ReserveNow",
            "2.0.1",
            ReserveNowResponse(status = ReserveNowAccepted),
        )
        @test true
    end

    @testset "GetCompositeSchedule req+resp" begin
        py_validate_request(
            "GetCompositeSchedule",
            "2.0.1",
            GetCompositeScheduleRequest(duration = 3600, evse_id = 1),
        )
        py_validate_response(
            "GetCompositeSchedule",
            "2.0.1",
            GetCompositeScheduleResponse(status = GenericAccepted),
        )
        @test true
    end

    @testset "TriggerMessage req+resp" begin
        py_validate_request(
            "TriggerMessage",
            "2.0.1",
            TriggerMessageRequest(
                requested_message = MessageTriggerBootNotification,
                evse = EVSE(id = 1),
            ),
        )
        py_validate_response(
            "TriggerMessage",
            "2.0.1",
            TriggerMessageResponse(status = TriggerMessageAccepted),
        )
        @test true
    end

    @testset "GetBaseReport req+resp" begin
        py_validate_request(
            "GetBaseReport",
            "2.0.1",
            GetBaseReportRequest(
                request_id = 1,
                report_base = ConfigurationInventory,
            ),
        )
        py_validate_response(
            "GetBaseReport",
            "2.0.1",
            GetBaseReportResponse(status = GenericDeviceModelAccepted),
        )
        @test true
    end

    @testset "GetLog req+resp" begin
        py_validate_request(
            "GetLog",
            "2.0.1",
            GetLogRequest(
                log_type = DiagnosticsLog,
                request_id = 1,
                log = LogParameters(
                    remote_location = "https://logs.example.com/upload",
                ),
            ),
        )
        py_validate_response(
            "GetLog",
            "2.0.1",
            GetLogResponse(status = LogAccepted),
        )
        @test true
    end

    @testset "UpdateFirmware req+resp" begin
        py_validate_request(
            "UpdateFirmware",
            "2.0.1",
            UpdateFirmwareRequest(
                request_id = 1,
                firmware = Firmware(
                    location = "https://firmware.example.com/fw-2.0.bin",
                    retrieve_date_time = "2025-06-01T00:00:00Z",
                ),
                retries = 3,
                retry_interval = 60,
            ),
        )
        py_validate_response(
            "UpdateFirmware",
            "2.0.1",
            UpdateFirmwareResponse(status = UpdateFirmwareAccepted),
        )
        @test true
    end

    @testset "ClearDisplayMessage req+resp" begin
        py_validate_request(
            "ClearDisplayMessage",
            "2.0.1",
            ClearDisplayMessageRequest(id = 1),
        )
        py_validate_response(
            "ClearDisplayMessage",
            "2.0.1",
            ClearDisplayMessageResponse(status = ClearMessageAccepted),
        )
        @test true
    end

    @testset "CostUpdated req+resp" begin
        py_validate_request(
            "CostUpdated",
            "2.0.1",
            CostUpdatedRequest(total_cost = 15.50, transaction_id = "tx-001"),
        )
        py_validate_response("CostUpdated", "2.0.1", CostUpdatedResponse())
        @test true
    end

    @testset "GetTransactionStatus req+resp" begin
        py_validate_request(
            "GetTransactionStatus",
            "2.0.1",
            GetTransactionStatusRequest(transaction_id = "tx-001"),
        )
        py_validate_response(
            "GetTransactionStatus",
            "2.0.1",
            GetTransactionStatusResponse(messages_in_queue = false),
        )
        @test true
    end

    @testset "RequestStartTransaction req+resp" begin
        py_validate_request(
            "RequestStartTransaction",
            "2.0.1",
            RequestStartTransactionRequest(
                id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
                remote_start_id = 1,
            ),
        )
        py_validate_response(
            "RequestStartTransaction",
            "2.0.1",
            RequestStartTransactionResponse(status = RequestStartStopAccepted),
        )
        @test true
    end

    @testset "RequestStopTransaction req+resp" begin
        py_validate_request(
            "RequestStopTransaction",
            "2.0.1",
            RequestStopTransactionRequest(transaction_id = "tx-001"),
        )
        py_validate_response(
            "RequestStopTransaction",
            "2.0.1",
            RequestStopTransactionResponse(status = RequestStartStopAccepted),
        )
        @test true
    end
end
