using OCPPData
using Documenter

DocMeta.setdocmeta!(OCPPData, :DocTestSetup, :(using OCPPData); recursive = true)

const page_rename = Dict("developer.md" => "Developer docs") # Without the numbers
const numbered_pages = [
    file for file in readdir(joinpath(@__DIR__, "src")) if
    file != "index.md" && splitext(file)[2] == ".md"
]

makedocs(;
    modules = [OCPPData],
    authors = "Stefan de Lange <langestefan@msn.com>",
    repo = "https://github.com/JuliaSolarPV/OCPPData.jl/blob/{commit}{path}#{line}",
    sitename = "OCPPData.jl",
    format = Documenter.HTML(; canonical = "https://JuliaSolarPV.github.io/OCPPData.jl"),
    pages = ["index.md"; numbered_pages],
)

deploydocs(; repo = "github.com/JuliaSolarPV/OCPPData.jl")
