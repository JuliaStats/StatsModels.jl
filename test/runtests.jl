using Compat
using Compat.Test
using Compat.LinearAlgebra
using Compat.SparseArrays

using StatsModels
using DataFrames
using StatsBase

using StatsModels: ContrastsMatrix

my_tests = ["formula.jl",
            "modelmatrix.jl",
            "statsmodel.jl",
            "contrasts.jl",
            "deprecated.jl"]

@testset "StatsModels" begin
    for tf in my_tests
        include(tf)
    end
end
