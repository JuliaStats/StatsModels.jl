module StatsModels

using Tables
using StatsBase
using ShiftedArrays
using ShiftedArrays: lag, lead
using DataStructures
using DataAPI: levels

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
    protect,
    unprotect
    
# copied from Compat: only
# https://github.com/JuliaLang/julia/pull/33129
if VERSION < v"1.4.0-DEV.142"
    export only


    Base.@propagate_inbounds function only(x)
        i = iterate(x)
        @boundscheck if i === nothing
            throw(ArgumentError("Collection is empty, must contain exactly 1 element"))
        end
        (ret, state) = i
        @boundscheck if iterate(x, state) !== nothing
            throw(ArgumentError("Collection has multiple elements, must contain exactly 1 element"))
        end
        return ret
    end


    # Collections of known size
    only(x::Ref) = x[]
    only(x::Number) = x
    only(x::Char) = x
    only(x::Tuple{Any}) = x[1]
    only(x::Tuple) = throw(
        ArgumentError("Tuple contains $(length(x)) elements, must contain exactly 1 element")
    )
    only(a::AbstractArray{<:Any, 0}) = @inbounds return a[]
    only(x::NamedTuple{<:Any, <:Tuple{Any}}) = first(x)
    only(x::NamedTuple) = throw(
        ArgumentError("NamedTuple contains $(length(x)) elements, must contain exactly 1 element")
    )
end

include("traits.jl")
include("contrasts.jl")
include("terms.jl")
include("schema.jl")
include("temporal_terms.jl")
include("formula.jl")
include("modelframe.jl")
include("statsmodel.jl")

end # module StatsModels
