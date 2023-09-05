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

"""
Wrapper for a `StatisticalModel` that has been fit from a `@formula` and tabular
data.

Most functions from the StatsBase API are simply delegated to the wrapped model,
with the exception of functions like `fit`, `predict`, and `coefnames` where the
tabular nature of the data means that additional processing is required or
information provided by the formula.

# Fields
* `model::M` the wrapped `StatisticalModel`.
* `mf::ModelFrame` encapsulates the formula, schema, and model type.
* `mm::ModelMatrix{T}` the model matrix that the model was fit from.
"""
struct TableStatisticalModel{M,T} <: StatisticalModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

"""
Wrapper for a `RegressionModel` that has been fit from a `@formula` and tabular
data.

Most functions from the StatsBase API are simply delegated to the wrapped model,
with the exception of functions like `fit`, `predict`, and `coefnames` where the
tabular nature of the data means that additional processing is required or
information provided by the formula.

# Fields
* `model::M` the wrapped `RegressioModel`.
* `mf::ModelFrame` encapsulates the formula, schema, and model type.
* `mm::ModelMatrix{T}` the model matrix that the model was fit from.
"""
struct TableRegressionModel{M,T} <: RegressionModel
    model::M
    mf::ModelFrame
    mm::ModelMatrix{T}
end

for (modeltype, dfmodeltype) in ((:StatisticalModel, TableStatisticalModel),
                                 (:RegressionModel, TableRegressionModel))
    @eval begin
        function StatsAPI.fit(::Type{T}, f::FormulaTerm, data, args...;
                               contrasts::Dict{Symbol,<:Any} = Dict{Symbol,Any}(),
                               kwargs...) where T<:$modeltype

            Tables.istable(data) || throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
            cols = columntable(data)

            mf = ModelFrame(f, cols, model=T, contrasts=contrasts)
            mm = ModelMatrix(mf)
            y = response(mf)
            $dfmodeltype(fit(T, mm.m, y, args...; kwargs...), mf, mm)

            ## TODO: consider doing this manually, without the ModelFrame/ModelMatrix
            # schema = schema(data, cols, contrasts)
            # f = apply_schema(f, schema, T)
            # y, X = modelcols(f, cols)
            # $dfmodeltype(fit(T, X, y, args...; kwargs...))
        end
    end
end

"""
    formula(model)

Retrieve formula from a fitted or specified model
"""
function formula end

formula(m::TableStatisticalModel) = m.mf.f
formula(m::TableRegressionModel) = m.mf.f

"""
    termnames(model::StatisticalModel)

Return the names of terms used in the formula of `model`.

This is a convenience method for `termnames(formula(model))`.

For `RegressionModel`s with only continuous predictors, this is the same as
`(responsename(model), coefnames(model))`.

For models with categorical predictors, the returned names reflect
the variable name and not the coefficients resulting from
the choice of contrast coding.
"""
termnames(model::StatisticalModel) = termnames(formula(model))

"""
    termnames(t::FormulaTerm)

Return a two-tuple of `termnames` applied to the left and
right hand sides of the formula.

Note that until `apply_schema` has been called, literal `1` in formulae
is interpreted as `ConstantTerm(1)` and will thus appear as `"1"` in the
returned term names.

```jldoctest
julia> termnames(@formula(y ~ 1 + x * y + (1+x|g)))
("y", ["1", "x", "y", "x & y", "(1 + x) | g"])
```

Similarly, formulae with an implicit intercept will not have a `"1"`
in their term names, because the implicit intercept does not exist until
`apply_schema` is called (and may not exist for certain model contexts).

```jldoctest
julia> termnames(@formula(y ~ x * y + (1+x|g)))
("y", ["x", "y", "x & y", "(1 + x) | g"])
```
"""
termnames(t::FormulaTerm) = (termnames(t.lhs), termnames(t.rhs))

"""
    termnames(term::AbstractTerm)

Return the name(s) of column(s) generated by a term.

Return value is either a `String`, an iterable of `String`s or nothing if there
no associated name (e.g. `termnames(InterceptTerm{false}())`).
"""
termnames(::InterceptTerm{H}) where {H} = H ? "(Intercept)" : nothing
termnames(t::ContinuousTerm) = string(t.sym)
termnames(t::CategoricalTerm) = string(t.sym)
termnames(t::Term) = string(t.sym)
termnames(t::ConstantTerm) = string(t.n)
termnames(t::FunctionTerm) = string(t.exorig)
termnames(ts::TupleTerm) = mapreduce(termnames, vcat, ts)
# these have some surprising behavior:
# termnames(::InteractionTerm) always returns a vector
# termnames(MatrixTerm(term(:a))) returns a scalar
# termnames(MatrixTerm((term(a:), term(:b)))) returns a vector
# but this is the same behavior as coefnames
termnames(t::MatrixTerm) = mapreduce(termnames, vcat, t.terms)
termnames(t::InteractionTerm) =
    kron_insideout((args...) -> join(args, " & "), vectorize.(termnames.(t.terms))...)

@doc """
    fit(Mod::Type{<:StatisticalModel}, f::FormulaTerm, data, args...;
        contrasts::Dict{Symbol}, kwargs...)

Convert tabular data into a numeric response vector and predictor matrix using
the formula `f`, and then `fit` the specified model type, wrapping the result in
a [`TableRegressionModel`](@ref) or [`TableStatisticalModel`](@ref) (as
appropriate).

This is intended as a backstop for modeling packages that implement model types
that are subtypes of `StatsAPI.StatisticalModel` but do not explicitly support
the full StatsModels terms-based interface.  Currently this works by creating a
[`ModelFrame`](@ref) from the formula and data, and then converting this to a
[`ModelMatrix`](@ref), but this is an internal implementation detail which may
change in the near future.
""" fit

# Delegate functions from StatsBase that use our new types
const TableModels = Union{TableStatisticalModel, TableRegressionModel}
@delegate TableModels.model [StatsAPI.coef, StatsAPI.confint,
                             StatsAPI.deviance, StatsAPI.nulldeviance,
                             StatsAPI.loglikelihood, StatsAPI.nullloglikelihood,
                             StatsAPI.dof, StatsAPI.dof_residual, StatsAPI.nobs,
                             StatsAPI.stderror, StatsAPI.vcov, StatsAPI.fitted]
@delegate TableRegressionModel.model [StatsAPI.modelmatrix,
                                      StatsAPI.residuals, StatsAPI.response,
                                      StatsAPI.predict, StatsAPI.predict!,
                                      StatsAPI.cooksdistance]
StatsAPI.predict(m::TableRegressionModel, new_x::AbstractMatrix; kwargs...) =
    predict(m.model, new_x; kwargs...)
# Need to define these manually because of ambiguity using @delegate

StatsAPI.r2(mm::TableRegressionModel) = r2(mm.model)
StatsAPI.adjr2(mm::TableRegressionModel) = adjr2(mm.model)
StatsAPI.r2(mm::TableRegressionModel, variant::Symbol) = r2(mm.model, variant)
StatsAPI.adjr2(mm::TableRegressionModel, variant::Symbol) = adjr2(mm.model, variant)
StatsAPI.loglikelihood(mm::TableModels, c::Colon) = loglikelihood(mm.model, c)

isnested(m1::TableModels, m2::TableModels; kwargs...) = isnested(m1.model, m2.model; kwargs...)

function _return_predictions(T, yp::AbstractVector, nonmissings, len)
    out = Vector{Union{eltype(yp),Missing}}(missing, len)
    out[nonmissings] = yp
    out
end

function _return_predictions(T, yp::AbstractMatrix, nonmissings, len)
    out = Matrix{Union{eltype(yp),Missing}}(missing, len, 3)
    out[nonmissings, :] = yp
    T((prediction = out[:,1], lower = out[:,2], upper = out[:,3]))
end

function _return_predictions(T, yp::NamedTuple, nonmissings, len)
    y = Vector{Union{eltype(yp.prediction),Missing}}(missing, len)
    l, h = similar(y), similar(y)
    out = (prediction = y, lower = l, upper = h)
    for key in (:prediction, :lower, :upper)
        out[key][nonmissings] = yp[key]
    end
    T(out)
end

# Predict function that takes data table as predictor instead of matrix
function StatsAPI.predict(mm::TableRegressionModel, data; kwargs...)
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))

    f = mm.mf.f
    cols, nonmissings = missing_omit(columntable(data), f.rhs)
    new_x = modelcols(f.rhs, cols)
    y_pred = predict(mm.model, reshape(new_x, size(new_x, 1), :);
                     kwargs...)
    _return_predictions(Tables.materializer(data), y_pred, nonmissings, length(nonmissings))
end

StatsAPI.coefnames(model::TableModels) = coefnames(model.mf)

# coeftable implementation
function StatsAPI.coeftable(model::TableModels; kwargs...)
    ct = coeftable(model.model, kwargs...)
    cfnames = coefnames(model.mf)
    if length(ct.rownms) == length(cfnames)
        ct.rownms = cfnames
    end
    ct
end

# show function that delegates to coeftable
function Base.show(io::IO, model::TableModels)
    println(io, typeof(model))
    println(io)
    println(io, model.mf.f)
    println(io)
    try
        println(io,"Coefficients:")
        show(io, coeftable(model))
    catch e
        if isa(e, MethodError) || isa(e, ErrorException) && occursin("coeftable is not defined", e.msg)
            show(io, model.model)
        else
            rethrow(e)
        end
    end
end
