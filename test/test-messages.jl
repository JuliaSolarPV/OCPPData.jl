@testitem "Messages" tags = [:fast] begin
    using OCPP
    using Test

    @testset "Call constructor" begin
        msg = Call("abc-123", "BootNotification", Dict{String,Any}("key" => "val"))
        @test msg.message_type_id == 2
        @test msg.unique_id == "abc-123"
        @test msg.action == "BootNotification"
        @test msg.payload == Dict{String,Any}("key" => "val")
    end

    @testset "CallResult constructor" begin
        msg = CallResult("abc-123", Dict{String,Any}("status" => "Accepted"))
        @test msg.message_type_id == 3
        @test msg.unique_id == "abc-123"
        @test msg.payload == Dict{String,Any}("status" => "Accepted")
    end

    @testset "CallError constructor" begin
        msg = CallError("abc-123", "NotImplemented", "No handler", Dict{String,Any}())
        @test msg.message_type_id == 4
        @test msg.unique_id == "abc-123"
        @test msg.error_code == "NotImplemented"
        @test msg.error_description == "No handler"
        @test msg.error_details == Dict{String,Any}()
    end

    @testset "Full constructor preserves message_type_id" begin
        msg = Call(2, "id", "Action", Dict{String,Any}())
        @test msg.message_type_id == 2
    end
end
