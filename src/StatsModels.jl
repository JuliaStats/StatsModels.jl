__precompile__(true)

module StatsModels

using Compat
using DataTables
using Distributions
using StatsBase
using NullableArrays
using CategoricalArrays


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
