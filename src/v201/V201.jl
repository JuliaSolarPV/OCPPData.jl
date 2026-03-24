module V201
using StructUtils
using JSON
import JSONSchema
using ..OCPPData: @generate_ocpp_types_from_definitions, AbstractOCPPSpec

struct Spec <: AbstractOCPPSpec end
export Spec

const _SCHEMA_DIR = joinpath(@__DIR__, "schemas")
@generate_ocpp_types_from_definitions _SCHEMA_DIR :V201_ACTIONS

const _SCHEMAS = Dict{String,JSONSchema.Schema}()
end # module V201
