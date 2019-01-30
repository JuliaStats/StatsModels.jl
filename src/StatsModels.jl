__precompile__(true)

module StatsModels

using DataFrames
using StatsBase
using SparseArrays
using LinearAlgebra

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

include("contrasts.jl")
include("formula.jl")
include("modelframe.jl")
include("modelmatrix.jl")
include("statsmodel.jl")
include("deprecated.jl")

end # module StatsModels
