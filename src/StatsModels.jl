module StatsModels

using Tables
using StatsBase
using ShiftedArrays
using ShiftedArrays: lag, lead
using DataStructures
using DataAPI
using DataAPI: levels
using Printf: @sprintf
using StatsFuns: chisqccdf

using SparseArrays
using LinearAlgebra

using Tables: ColumnTable

export
    #re-export from StatsBase:
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
    ContrastsCoding,
    
    coefnames,
    dropterm,
    setcontrasts!,
    formula,

    AbstractTerm,
    ConstantTerm,
    Term,
    ContinuousTerm,
    CategoricalTerm,
    InteractionTerm,
    FormulaTerm,
    InterceptTerm,
    FunctionTerm,
    LagTerm,
    MatrixTerm,

    lag, lead, # Rexported from ShiftedArrays

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

    lrtest

include("traits.jl")
include("contrasts.jl")
include("terms.jl")
include("schema.jl")
include("temporal_terms.jl")
include("formula.jl")
include("modelframe.jl")
include("statsmodel.jl")
include("lrtest.jl")

end # module StatsModels
