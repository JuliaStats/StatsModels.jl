##############################################################################
#
# A macro for doing delegation
#
# This macro call
#
#     @delegate MyContainer.elems [:size, :length, :ndims, :endof]
#
# produces this block of expressions
#
#     size(a::MyContainer) = size(a.elems)
#     length(a::MyContainer) = length(a.elems)
#     ndims(a::MyContainer) = ndims(a.elems)
#     endof(a::MyContainer) = endof(a.elems)
#
##############################################################################

macro delegate(source, targets)
    typename = esc(source.args[1])
    sourceargs2 = source.args[2]
    fieldname = Expr(:quote, isa(sourceargs2, QuoteNode) ? sourceargs2.value : sourceargs2.args[1])
    funcnames = targets.args
    n = length(funcnames)
    result = quote begin end end
    for i in 1:n
        funcname = esc(funcnames[i])
        f = quote
            ($funcname)(a::($typename), args...; kwargs...) = ($funcname)(getfield(a, $fieldname), args...; kwargs...)
        end
        push!(result.args[2].args, f)
    end
    return result
end

# Wrappers for DataFrameStatisticalModel and DataFrameRegressionModel
struct DataFrameStatisticalModel{M,T} <: StatisticalModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

struct DataFrameRegressionModel{M,T} <: RegressionModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

"""
    supports_intercept(::Type)

Define whether a given model supports intercept. Return `true` by default. To specify 
that a model type `T` does not support an intercept, overload this function for the 
corresponding type: `supports_intercept(::Type{T}) = false`

Models that do not support an intercept will be fitted without one: the intercept term 
will be removed even if explicitly provided by the user.
"""
supports_intercept(::Type) = true

for (modeltype, dfmodeltype) in ((:StatisticalModel, DataFrameStatisticalModel),
                                 (:RegressionModel, DataFrameRegressionModel))
    @eval begin
        function StatsBase.fit(::Type{T}, f::Formula, df::AbstractDataFrame,
                               args...; contrasts::Dict = Dict(), kwargs...) where T<:$modeltype
            trms = Terms(f)
            supports_intercept(T) || (trms.intercept = false)
            mf = ModelFrame(trms, df, contrasts=contrasts)
            mm = ModelMatrix(mf)
            y = model_response(mf)
            $dfmodeltype(fit(T, mm.m, y, args...; kwargs...), mf, mm)
        end
    end
end

# Delegate functions from StatsBase that use our new types
const DataFrameModels = Union{DataFrameStatisticalModel, DataFrameRegressionModel}
@delegate DataFrameModels.model [StatsBase.coef, StatsBase.confint,
                                 StatsBase.deviance, StatsBase.nulldeviance,
                                 StatsBase.loglikelihood, StatsBase.nullloglikelihood,
                                 StatsBase.dof, StatsBase.dof_residual, StatsBase.nobs,
                                 StatsBase.stderr, StatsBase.vcov]
@delegate DataFrameRegressionModel.model [StatsBase.residuals, StatsBase.model_response,
                                          StatsBase.predict, StatsBase.predict!]
# Need to define these manually because of ambiguity using @delegate
StatsBase.r2(mm::DataFrameRegressionModel) = r2(mm.model)
StatsBase.adjr2(mm::DataFrameRegressionModel) = adjr2(mm.model)
StatsBase.r2(mm::DataFrameRegressionModel, variant::Symbol) = r2(mm.model, variant)
StatsBase.adjr2(mm::DataFrameRegressionModel, variant::Symbol) = adjr2(mm.model, variant)

# Predict function that takes data frame as predictor instead of matrix
function StatsBase.predict(mm::DataFrameRegressionModel, df::AbstractDataFrame; kwargs...)
    # copy terms, removing outcome if present (ModelFrame will complain if a
    # term is not found in the DataFrame and we don't want to remove elements with missing y)
    newTerms = dropresponse!(mm.mf.terms)
    # create new model frame/matrix
    mf = ModelFrame(newTerms, df; contrasts = mm.mf.contrasts)
    newX = ModelMatrix(mf).m
    yp = predict(mm, newX; kwargs...)
    out = missings(eltype(yp), size(df, 1))
    out[mf.msng] = yp
    return(out)
end



# coeftable implementation
function StatsBase.coeftable(model::DataFrameModels)
    ct = coeftable(model.model)
    cfnames = coefnames(model.mf)
    if length(ct.rownms) == length(cfnames)
        ct.rownms = cfnames
    end
    ct
end

# show function that delegates to coeftable
function Base.show(io::IO, model::DataFrameModels)
    try
        ct = coeftable(model)
        println(io, "$(typeof(model))")
        println(io)
        println(io, Formula(model.mf.terms))
        println(io)
        println(io,"Coefficients:")
        show(io, ct)
    catch e
        if isa(e, ErrorException) && contains(e.msg, "coeftable is not defined")
            show(io, model.model)
        else
            rethrow(e)
        end
    end
end
