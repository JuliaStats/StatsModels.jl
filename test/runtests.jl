using Test
using LinearAlgebra
using SparseArrays

using StatsModels
using DataFrames
using StatsBase

using StatsModels: ContrastsMatrix

my_tests = ["formula.jl",
            "modelmatrix.jl",
            "statsmodel.jl",
            "contrasts.jl"]

@testset "StatsModels" begin
    for tf in my_tests
        include(tf)
    end
end
