using Test
using LinearAlgebra
using SparseArrays

using StatsModels
using DataFrames
using CategoricalArrays
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
            "traits.jl"]

@testset "StatsModels" begin
    for tf in my_tests
        include(tf)
    end
end
