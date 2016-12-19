```@meta
CurrentModule = StatsModels
DocTestSetup = quote
    using StatsModels
end
```

# Modeling tabular data

Most statistical models require that data be represented as a `Matrix`-like
collection of a single numeric type.  Much of the data we want to model,
however, is **tabular data**, where data is represented as a collection of
fields with possibly heterogeneous types.  One of the primary goals of
`StatsModels` is to make it simpler to transform tabular data into matrix format
suitable for statistical modeling.

At the moment, "tabular data" means an `AbstractDataFrame`.  Ultimately, the
goal is to support any tabular data format that adheres to a minimal API,
**regardless of backend**.

## The `Formula` type

The basic conceptual tool for this is the `Formula`, which has a left side and a
right side, separated by `~`. Formulas are constructed using the `@formula` macro:

```jldoctest
julia> @formula(y ~ 1 + a)
Formula: y ~ 1 + a
```

Note that the `@formula` macro **must** be called with parentheses to ensure that
the formula is parsed properly.

The left side of a formula conventionally represents *dependent* variables, and
the right side *independent* variables (or regressors).  *Terms* are separated
by `+`.  Basic terms are the integers `1` or `0`—evaluated as the presence or
absence of a constant intercept term, respectively—and variables like `x`,
which will evaluate to the data source column with that name as a symbol (`:x`).

Individual variables can be combined into *interaction terms* with `&`, as in
`a&b`, which will evaluate to the product of the columns named `:a` and `:b`.
If either `a` or `b` are categorical, then the interaction term `a&b` generates
all the product of each pair of the columns of `a` and `b`.

It's often convenient to include main effects and interactions for a number of
variables.  The `*` operator does this, expanding in the following way:

```jldoctest
julia> Formula(StatsModels.Terms(@formula(y ~ 1 + a*b)))
Formula: y ~ 1 + a + b + a & b
```

(We trigger parsing of the formula using the internal `Terms` type to show how
the `Formula` expands).

This applies to higher-order interactions, too: `a*b*c` expands to the main
effects, all two-way interactions, and the three way interaction `a&b&c`:

```jldoctest
julia> Formula(StatsModels.Terms(@formula(y ~ 1 + a*b*c)))
Formula: y ~ 1 + a + b + c + a & b + a & c + b & c + &(a,b,c)
```

Both the `*` and the `&` operators act like multiplication, and are distributive
over addition:

```jldoctest
julia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) & c)))
Formula: y ~ 1 + c & a + c & b

julia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) * c)))
Formula: y ~ 1 + a + b + c + c & a + c & b
```

## The `ModelFrame` and `ModelMatrix` types

The main use of `Formula`s is for fitting statistical models based on tabular
data.  From the user's perspective, this is done by `fit` methods that take a
`Formula` and a `DataFrame` instead of numeric matrices.

Internally, this is accomplished in three stages:

1. The `Formula` is parsed into [`Terms`](@ref).
2. The `Terms` and the data source are wrapped in a [`ModelFrame`](@ref).
3. A numeric [`ModelMatrix`](@ref) is generated from the `ModelFrame` and passed to the
   model's `fit` method.

```@docs
ModelFrame
ModelMatrix
Terms
```
