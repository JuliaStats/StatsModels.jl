using Compat
using StatsModels
using Test

using DataFrames
using StatsBase

using StatsModels: ContrastsMatrix

using Compat.LinearAlgebra
using Compat.SparseArrays

my_tests = ["formula.jl",
            "modelmatrix.jl",
            "statsmodel.jl",
            "contrasts.jl"]

@testset "StatsModels" begin
    for tf in my_tests
        include(tf)
    end
end
