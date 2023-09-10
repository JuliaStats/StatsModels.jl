# putting this behind a function barrier means that the model matrix
# can potentially be freed immediately if it's large and constructed on the fly
function _find_intercept(model::RegressionModel)
    modelmat = modelmatrix(model)
    cols = eachcol(modelmat)
    # XXX collect is necessary for Julia 1.6
    # but it's :just: an array of references to views, so shouldn't be too
    # expensive
    @static if VERSION < v"1.7"
        cols = collect(cols)
    end
    return findfirst(Base.Fix1(all, isone), cols)
end

_find_intercept(form::FormulaTerm) = _find_intercept(form.rhs)
# we need these in case the RHS is a single term
_find_intercept(::AbstractTerm) = nothing
_find_intercept(::InterceptTerm{true}) = 1
_find_intercept(m::MatrixTerm) = _find_intercept(m.terms)
function _find_intercept(t::TupleTerm) 
    return findfirst(Base.Fix2(isa, InterceptTerm{true}), t)
end

# borrowed from Effects.jl
function get_matrix_term(x)
    x = collect_matrix_terms(x)
    x = x isa MatrixTerm ? x : first(x)
    x isa MatrixTerm || throw(ArgumentError("couldn't extract matrix term from $x"))
    if first(x.terms) isa MatrixTerm
        x = only(x.terms)
    end
    return x
end

function StatsAPI.vif(model::RegressionModel)
    vc = vcov(model)
    Base.require_one_based_indexing(vc)

    intercept = _find_intercept(model)
    isnothing(intercept) &&
        throw(ArgumentError("VIF is only defined for models with an intercept term"))

    # copy just in case vc was a reference to an internal structure
    vc = StatsBase.cov2cor!(copy(vc), stderror(model))
    m = view(vc, axes(vc, 1) .!= intercept, axes(vc, 2) .!= intercept)
    size(m, 2) > 1 ||
        throw(ArgumentError("VIF not meaningful for models with only one non-intercept term"))
    # NB: The correlation matrix is positive definite and hence invertible
    #     unless there is perfect rank deficiency, hence the warning in the docstring.
    return diag(inv(m))
end


"""
    gvif(model::RegressionModel; scale=false)

Compute the generalized variance inflation factor (GVIF).

If `scale=true`, then each GVIF is scaled by the degrees of freedom
for (number of coefficients associated with) the predictor: ``GVIF^(1 / (2*df))``.

Returns a vector of inflation factors computed for each term except
for the intercept.
In other words, the corresponding coefficients are `termnames(m)[2:end]`.

The [GVIF](https://doi.org/10.2307/2290467)
measures the increase in the variance of a (group of) parameter's estimate in a model
with multiple parameters relative to the variance of a parameter's estimate in a
model containing only that parameter. For continuous, numerical predictors, the GVIF
is the same as the VIF, but for categorical predictors, the GVIF provides a single
number for the entire group of contrast-coded coefficients associated with a categorical
predictor.

See also [`termnames`](@ref), [`vif`](@ref).

!!! warning
    This method will fail if there is (numerically) perfect multicollinearity,
    i.e. rank deficiency (in the fixed effects). In that case though, the VIF
    isn't particularly informative anyway.

## References

Fox, J., & Monette, G. (1992). Generalized Collinearity Diagnostics.
Journal of the American Statistical Association, 87(417), 178. doi:10.2307/2290467
"""
function StatsAPI.gvif(model::RegressionModel; scale=false)
    form = formula(model)
    intercept = _find_intercept(form)
    isnothing(intercept) &&
        throw(ArgumentError("GVIF only defined for models with an intercept term"))
    vc = vcov(model)
    Base.require_one_based_indexing(vc)

    vc = StatsBase.cov2cor!(copy(vc), stderror(model))
    m = view(vc, axes(vc, 1) .!= intercept, axes(vc, 2) .!= intercept)
    size(m, 2) > 1 ||
        throw(ArgumentError("GVIF not meaningful for models with only one non-intercept term"))

    tn = last(termnames(model))
    tn = view(tn, axes(tn, 1) .!= intercept)
    trms = get_matrix_term(form.rhs).terms
    # MatrixTerms.terms is a tuple or vector so always 1-based indexing
    trms = [trms[i] for i in 1:length(trms) if i != intercept]

    df = width.(trms)
    vals = zeros(eltype(m), length(tn))
    logdetm = logdet(m)
    acc = 0
    for idx in axes(vals, 1)
        wt = df[idx]
        trm_only = [acc < i <= (acc + wt) for i in axes(m, 2)]
        trm_excl = .!trm_only
        vals[idx] = exp(logdet(view(m, trm_only, trm_only)) +
                        logdet(view(m, trm_excl, trm_excl)) -
                        logdetm)
        acc += wt
    end

    if scale
        vals .= vals .^ (1 ./ (2 .* df))
    end
    return vals
end
