module StatsModels

using Tables
using StatsAPI
using StatsBase
using ShiftedArrays
using ShiftedArrays: lag, lead
using DataStructures
using DataAPI
using DataAPI: levels
using Printf: @sprintf
using StatsAPI: coefnames, fit, predict, predict!
using StatsFuns: chisqccdf

using SparseArrays
using LinearAlgebra

using Tables: ColumnTable

using REPL: levenshtein

export
    #reexport from StatsBase:
    StatisticalModel,
    RegressionModel,

    @formula,
    ModelFrame,
    ModelMatrix,

    AbstractContrasts,
    EffectsCoding,
    DummyCoding,
    HelmertCoding,
    SeqDiffCoding,
    HypothesisCoding,

    coefnames,
    setcontrasts!,
    formula,
    termnames,

    AbstractTerm,
    ConstantTerm,
    Term,
    ContinuousTerm,
    CategoricalTerm,
    InteractionTerm,
    FormulaTerm,
    InterceptTerm,
    FunctionTerm,
    MatrixTerm,

    lag, lead, # Reexported from ShiftedArrays

    term,
    terms,
    drop_term,
    schema,
    concrete_term,
    apply_schema,
    width,
    modelcols,
    modelmatrix,
    response,
    protect,
    unprotect,

    hasintercept,
    omitsintercept,
    hasresponse,

    lrtest

const SPECIALS = (:+, :&, :*, :~)

include("traits.jl")
include("contrasts.jl")
include("terms.jl")
include("errormessages.jl")
include("schema.jl")
include("temporal_terms.jl")
include("formula.jl")
include("modelframe.jl")
include("statsmodel.jl")
include("lrtest.jl")

end # module StatsModels
