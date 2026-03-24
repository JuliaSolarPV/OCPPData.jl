module V16
using StructUtils
using JSON
import JSONSchema
using ..OCPPData: @generate_ocpp_types, AbstractOCPPSpec

struct Spec <: AbstractOCPPSpec end
export Spec

include("registries.jl")

const _SCHEMA_DIR = joinpath(@__DIR__, "schemas")
@generate_ocpp_types _SCHEMA_DIR V16_ENUM_REGISTRY V16_NESTED_TYPE_NAMES :V16_ACTIONS

const _SCHEMAS = Dict{String,JSONSchema.Schema}()
end # module V16
