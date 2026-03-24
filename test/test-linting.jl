
@testitem "Aqua" tags = [:linting] begin
    using Aqua: Aqua
    using OCPPData

    Aqua.test_all(OCPPData)
end

@testitem "JET" tags = [:linting] begin
    if v"1.12" <= VERSION < v"1.13"
        using JET: JET
        using OCPPData

        JET.test_package(OCPPData; target_modules = (OCPPData,))
    end
end
