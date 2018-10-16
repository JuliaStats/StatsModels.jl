__precompile__(false)

module StatsModels

using Tables
using OnlineStats
using StatsBase
using CategoricalArrays

using SparseArrays
using LinearAlgebra
using Missings

using Tables: ColumnTable
using StatsBase: StatisticalModel

export
    @formula,
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
    FunctionTerm,

    term,
    terms,
    drop_term,
    schema,
    apply_schema,
    width,
    model_cols,
    model_matrix,
    model_response

include("traits.jl")
include("contrasts.jl")
include("terms.jl")
include("schema.jl")
include("formula.jl")
include("modelframe.jl")
# include("statsmodel.jl")

end # module StatsModels
