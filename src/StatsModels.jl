__precompile__(false)

module StatsModels

using Compat
using DataFrames
using DataStreams
using OnlineStats
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
       setcontrasts!,

    AbstractTerm,
    TermOrTerms,
    Term,
    ContinuousTerm,
    CategoricalTerm,
    InteractionTerm,
    FormulaTerm,
    InterceptTerm,

    
    schema,
    apply_schema,
    width,
    model_cols

include("contrasts.jl")
include("terms.jl")
include("schema.jl")
include("formula.jl")
include("modelframe.jl")
include("modelmatrix.jl")
include("statsmodel.jl")
include("deprecated.jl")


end # module StatsModels
