using Test
using Aqua
using LinearAlgebra
using SparseArrays
using TestSetExtensions

using StatsModels
using DataFrames
using CategoricalArrays
using StatsAPI
using StatsBase

using StatsAPI: dof
using StatsModels: ContrastsMatrix

my_tests = ["ambiguity.jl",
            "formula.jl",
            "terms.jl",
            "temporal_terms.jl",
            "schema.jl",
            "modelmatrix.jl",
            "modelframe.jl",
            "statsmodel.jl",
            "contrasts.jl",
            "extension.jl",
            "traits.jl",
            "protect.jl",
            "vif.jl"]

@testset ExtendedTestSet "StatsModels" begin
    @testset "aqua" begin
        # because VIF and GVIF are defined in StatsAPI for RegressionModel,
        # which is also defined there, it's flagged as piracy. But
        # we're the offical implementers so it's privateering.
        Aqua.test_all(StatsModels; ambiguities=false, piracy=(treat_as_own=[vif, gvif],))
    end

    for tf in my_tests
        include(tf)
    end
end
