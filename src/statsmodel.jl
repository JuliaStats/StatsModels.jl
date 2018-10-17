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

# Wrappers for TableStatisticalModel and TableRegressionModel
struct TableStatisticalModel{M,T} <: StatisticalModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

struct TableRegressionModel{M,T} <: RegressionModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

"""
    drop_intercept(::Type)

Define whether a given model automatically drops the intercept. Return `false` by default. 
To specify that a model type `T` drops the intercept, overload this function for the 
corresponding type: `drop_intercept(::Type{T}) = true`

Models that drop the intercept will be fitted without one: the intercept term will be 
removed even if explicitly provided by the user. Categorical variables will be expanded 
in the rank-reduced form (contrasts for `n` levels will only produce `n-1` columns).
"""
drop_intercept(::Type) = false

for (modeltype, dfmodeltype) in ((:StatisticalModel, TableStatisticalModel),
                                 (:RegressionModel, TableRegressionModel))
    @eval begin
        function StatsBase.fit(::Type{T}, f::FormulaTerm, data, args...;
                               contrasts::Dict{Symbol,<:Any} = Dict{Symbol,Any}(),
                               kwargs...) where T<:$modeltype
                               
            Tables.istable(data) || throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
            cols = columntable(data)

            mf = ModelFrame(f, cols, mod=T, contrasts=contrasts)
            mm = ModelMatrix(mf)
            y = model_response(mf)
            $dfmodeltype(fit(T, mm.m, y, args...; kwargs...), mf, mm)

            ## TODO: consider doing this manually, without the ModelFrame/ModelMatrix
            # schema = schema(data, cols, contrasts)
            # f = apply_schema(f, schema, T)
            # y, X = model_cols(f, cols)
            # $dfmodeltype(fit(T, X, y, args...; kwargs...))
        end
    end
end

# Delegate functions from StatsBase that use our new types
const TableModels = Union{TableStatisticalModel, TableRegressionModel}
@delegate TableModels.model [StatsBase.coef, StatsBase.confint,
                             StatsBase.deviance, StatsBase.nulldeviance,
                             StatsBase.loglikelihood, StatsBase.nullloglikelihood,
                             StatsBase.dof, StatsBase.dof_residual, StatsBase.nobs,
                             StatsBase.stderror, StatsBase.vcov]
@delegate TableRegressionModel.model [StatsBase.residuals, StatsBase.model_response,
                                      StatsBase.predict, StatsBase.predict!]
StatsBase.predict(m::TableRegressionModel, new_x::AbstractMatrix; kwargs...) =
    predict(m.model, new_x; kwargs...)
# Need to define these manually because of ambiguity using @delegate
StatsBase.r2(mm::TableRegressionModel) = r2(mm.model)
StatsBase.adjr2(mm::TableRegressionModel) = adjr2(mm.model)
StatsBase.r2(mm::TableRegressionModel, variant::Symbol) = r2(mm.model, variant)
StatsBase.adjr2(mm::TableRegressionModel, variant::Symbol) = adjr2(mm.model, variant)

# Predict function that takes data frame as predictor instead of matrix
function StatsBase.predict(mm::TableRegressionModel, data; kwargs...)
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))

    f = mm.mf.f
    cols, nonmissings = missing_omit(columntable(data), f)
    new_x = model_cols(f.rhs, cols)
    y_pred = predict(mm.model, reshape(new_x, size(new_x, 1), :);
                     kwargs...)
    out = missings(eltype(y_pred), size(data, 1))
    out[nonmissings] .= y_pred
    return out
end

StatsBase.coefnames(model::TableModels) = coefnames(model.mf)

# coeftable implementation
function StatsBase.coeftable(model::TableModels)
    ct = coeftable(model.model)
    cfnames = coefnames(model.mf)
    if length(ct.rownms) == length(cfnames)
        ct.rownms = cfnames
    end
    ct
end

# show function that delegates to coeftable
function Base.show(io::IO, model::TableModels)
    try
        ct = coeftable(model)
        println(io, typeof(model))
        println(io)
        println(io, model.mf.f)
        println(io)
        println(io,"Coefficients:")
        show(io, ct)
    catch e
        if isa(e, ErrorException) && occursin("coeftable is not defined", e.msg)
            show(io, model.model)
        else
            rethrow(e)
        end
    end
end
