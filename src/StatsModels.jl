__precompile__(true)

module StatsModels

using Compat
using ArgCheck
using DataFrames
using StatsBase
using Compat.SparseArrays
using Compat.LinearAlgebra
using Compat: @debug

export @formula,
       Formula,
       ModelFrame,
       ModelMatrix,

       AbstractContrasts,
       EffectsCoding,
       DummyCoding,
       HelmertCoding,
       ContrastsCoding,

       coefnames,
       dropterm,
       setcontrasts!

map(include,
    [
        "contrasts.jl",
        "formula.jl",
        "modelframe.jl",
        "modelmatrix.jl",
        "statsmodel.jl"
    ])


end # module StatsModels
