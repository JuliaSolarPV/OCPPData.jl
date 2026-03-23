# Cross-validation tests: serialize Julia types to JSON, validate with Python ocpp library
# via PythonCall.jl + CondaPkg.jl.
#
# Run:
#   julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->(:crossvalidation in ti.tags) verbose=true'

@testsnippet PythonOCPP begin
    using CondaPkg
    CondaPkg.add_pip("ocpp"; version = ">=2.0.0")
    using PythonCall
    import JSON

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

# ---------------------------------------------------------------------------
# V16
# ---------------------------------------------------------------------------

@testitem "Python cross-validation: OCPP 1.6" tags = [:crossvalidation] setup = [PythonOCPP] begin
    using OCPP.V16
    using Test

    @testset "BootNotification" begin
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

    @testset "Heartbeat" begin
        py_validate_request("Heartbeat", "1.6", HeartbeatRequest())
        @test true
    end

    @testset "Authorize" begin
        py_validate_request("Authorize", "1.6", AuthorizeRequest(id_tag = "RFID1234"))
        @test true
    end

    @testset "StartTransaction" begin
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
        @test true
    end

    @testset "StopTransaction" begin
        py_validate_request(
            "StopTransaction",
            "1.6",
            StopTransactionRequest(
                meter_stop = 5000,
                timestamp = "2025-01-01T13:00:00Z",
                transaction_id = 42,
            ),
        )
        @test true
    end

    @testset "StatusNotification" begin
        py_validate_request(
            "StatusNotification",
            "1.6",
            StatusNotificationRequest(
                connector_id = 1,
                error_code = NoError,
                status = ChargePointAvailable,
            ),
        )
        @test true
    end

    @testset "MeterValues" begin
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
        @test true
    end

    @testset "SetChargingProfile (float limit 21.4)" begin
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
        @test true
    end

    @testset "ChangeConfiguration" begin
        py_validate_request(
            "ChangeConfiguration",
            "1.6",
            ChangeConfigurationRequest(key = "HeartbeatInterval", value = "300"),
        )
        @test true
    end

    @testset "Reset" begin
        py_validate_request("Reset", "1.6", ResetRequest(type = ResetHard))
        @test true
    end
end

# ---------------------------------------------------------------------------
# V201
# ---------------------------------------------------------------------------

@testitem "Python cross-validation: OCPP 2.0.1" tags = [:crossvalidation] setup =
    [PythonOCPP] begin
    using OCPP.V201
    using Test

    @testset "BootNotification" begin
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

    @testset "Heartbeat" begin
        py_validate_request("Heartbeat", "2.0.1", HeartbeatRequest())
        @test true
    end

    @testset "Authorize" begin
        py_validate_request(
            "Authorize",
            "2.0.1",
            AuthorizeRequest(
                id_token = IdToken(id_token = "RFID1234", type = IdTokenCentral),
            ),
        )
        @test true
    end

    @testset "TransactionEvent" begin
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
        @test true
    end

    @testset "StatusNotification" begin
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
        @test true
    end

    @testset "GetVariables" begin
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
        @test true
    end

    @testset "Reset" begin
        py_validate_request("Reset", "2.0.1", ResetRequest(type = Immediate))
        @test true
    end
end
