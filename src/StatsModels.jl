__precompile__(true)

module StatsModels

using Compat
using DataStreams
using StatsBase
using Compat.SparseArrays
using Compat.LinearAlgebra
using Compat: @debug, @warn

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
