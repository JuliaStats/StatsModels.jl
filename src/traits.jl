# Traits used for statistical models

implicit_intercept(x::T) where {T} = implicit_intercept(T)
implicit_intercept(::Type{T}) where {T} = false
implicit_intercept(::Type{<:StatisticalModel}) = true

drop_intercept(x::T) where {T} = drop_intercept(T)
drop_intercept(::Type{T}) where {T} = false
drop_intercept(::Type{<:StatisticalModel}) = false
