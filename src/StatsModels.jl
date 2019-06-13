module StatsModels

using Tables
using StatsBase
import ShiftedArrays: lag, lead  # need to use import, not using, to add docstrings
using CategoricalArrays
using DataStructures

using SparseArrays
using LinearAlgebra
using Missings

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
    ContrastsCoding,

    coefnames,
    dropterm,
    setcontrasts!,

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
    response

include("traits.jl")
include("contrasts.jl")
include("terms.jl")
include("temporal_terms.jl")
include("schema.jl")
include("formula.jl")
include("modelframe.jl")
include("statsmodel.jl")

end # module StatsModels
