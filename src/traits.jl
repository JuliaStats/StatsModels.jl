# Traits used for statistical models

implicit_intercept(x::T) where {T} = implicit_intercept(T)
implicit_intercept(::Type{T}) where {T} = false
implicit_intercept(::Type{<:StatisticalModel}) = true

"""
    drop_intercept(::Type)

Define whether a given model automatically drops the intercept. Return `false` by default. 
To specify that a model type `T` drops the intercept, overload this function for the 
corresponding type: `drop_intercept(::Type{T}) = true`

Models that drop the intercept will be fitted without one: the intercept term will be 
removed even if explicitly provided by the user. Categorical variables will be expanded 
in the rank-reduced form (contrasts for `n` levels will only produce `n-1` columns).
"""
drop_intercept(x::T) where {T} = drop_intercept(T)
drop_intercept(::Type{T}) where {T} = false
drop_intercept(::Type{<:StatisticalModel}) = false
