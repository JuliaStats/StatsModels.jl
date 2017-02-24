__precompile__(true)

module StatsModels

using Compat
using TableBase
using TableBase: Table
# using DataTables
using StatsBase
# using NullableArrays
# using CategoricalArrays


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

# TEMPORARY DEFINITIONS
const AbstractCategoricalVector = Any


map(include,
    [
        "contrasts.jl",
        "formula.jl",
        "modelframe.jl",
        "modelmatrix.jl",
        "statsmodel.jl"
    ])


end # module StatsModels
