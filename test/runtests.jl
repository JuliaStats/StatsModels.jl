using Test
using Aqua
using LinearAlgebra
using SparseArrays

using StatsModels
using DataFrames
using CategoricalArrays
using StatsAPI
using StatsBase

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
            "protect.jl"]

@testset "StatsModels" begin
    @testset "aqua" begin
        Aqua.test_all(StatsModels; ambiguities=false)
    end

    for tf in my_tests
        include(tf)
    end
end
