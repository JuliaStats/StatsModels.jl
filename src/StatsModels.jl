__precompile__(false)

module StatsModels

using DataFrames
using DataStreams
using OnlineStats
using StatsBase
using SparseArrays
using LinearAlgebra
using Missings

export @formula,
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
    ConstantTerm,
    Term,
    ContinuousTerm,
    CategoricalTerm,
    InteractionTerm,
    FormulaTerm,
    InterceptTerm,

    term,
    terms,
    drop_term,
    schema,
    apply_schema,
    width,
    model_cols,
    model_matrix,
    model_response

include("contrasts.jl")
include("terms.jl")
include("schema.jl")
include("formula.jl")
include("modelframe2.jl")
# include("modelmatrix.jl")
# include("statsmodel.jl")
# include("deprecated.jl")


end # module StatsModels
