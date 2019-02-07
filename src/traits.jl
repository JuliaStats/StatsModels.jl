# Traits used for statistical models

"""
    implicit_intercept(T::Type)
    implicit_intercept(x::T) = implicit_intercept(T)

Return `true` if models of type `T` should include an implicit intercept even
if none is specified in the formula.  Is `true` by default for all
`T<:StatisticalModel`, and `false` for others.  To specify that a model type `T`
includes an intercept even if one is not specified explicitly in the formula,
overload this function for the corresponding type:
`implicit_intercept(::Type{<:T}) = true`

If a model has an implicit intercept, it can be explicitly excluded by using `0`
in the formula, which generates [`InterceptTerm{false}`](@ref InterceptTerm) with
[`apply_schema`](@ref).
"""
implicit_intercept(x::T) where {T} = implicit_intercept(T)
implicit_intercept(::Type{T}) where {T} = false
implicit_intercept(::Type{<:StatisticalModel}) = true

"""
    drop_intercept(T::Type)
    drop_intercept(x::T) = drop_intercept(T)

Define whether a given model automatically drops the intercept. Return `false` by default. 
To specify that a model type `T` drops the intercept, overload this function for the 
corresponding type: `drop_intercept(::Type{<:T}) = true`

Models that drop the intercept will be fitted without one: the intercept term will be 
removed even if explicitly provided by the user. Categorical variables will be expanded 
in the rank-reduced form (contrasts for `n` levels will only produce `n-1` columns).
"""
drop_intercept(x::T) where {T} = drop_intercept(T)
drop_intercept(::Type) = false
