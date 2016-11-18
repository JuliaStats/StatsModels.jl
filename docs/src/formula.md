```@meta
CurrentModule = StatsModels
DocTestSetup = quote
    using StatsModels
end
```

# Modeling tabular data

Most statistical models require that data be represented as a `Matrix`-like
collection of a single numeric type.  Much of the data we want to model,
however, is __tabular data__, where data is represented as a collection of
fields with possibly heterogeneous types.  One of the primary goals of
`StatsModels` is to make it simpler to transform tabular data into matrix format
suitable for statistical modeling.

At the moment, "tabular data" means an `AbstractDataFrame`.  Ultimately, the
goal is to support any tabular data format that adheres to a minimal API,
__regardless of backend__.

## The `Formula` type

The basic conceptual tool for this is the `Formula`, which has a left side and a
right side, separated by `~`:

```jldoctest
julia> y ~ 1 + x
Formula: y ~ 1 + x
```

The left side of a formula conventionally represents _dependent_ variables, and
the right side _independent_ variables (or regressors).  _Terms_ are separated
by `+`.  Basic terms are the integers `1` or `0`—evaluated as the presence or
absence of a constant intercept term, respectively—and variables like `x`,
which will evaluate to the data source column with that name as a symbol (`:x`).

Individual variables can be combined into _interaction terms_ with `&`, as in
`x&z`, which will evaluate to the product of the columns named `:x` and `:z`.
Because it's often convenient to include main effects and interactions for a
number of variables, the `*` operator will expand in the following way:

```jldoctest
julia> Formula(StatsModels.Terms(a ~ 1 + x*y)) # Parse by converting to Terms
Formula: a ~ 1 + x + y + x & y
```

This applies to higher-order interactions, too: `x*y*z` expands to the main
effects, all two-way interactions, and the three way interaction `x&y&z`:

```jldoctest
julia> Formula(StatsModels.Terms(a ~ 1 + x*y*z))
Formula: a ~ 1 + x + y + z + x & y + x & z + y & z + &(x,y,z)
```

Both the `*` and the `&` operators act like multiplication, and are distributive
over addition:

```jldoctest
julia> Formula(StatsModels.Terms(y ~ 1 + (a+b) & c))
Formula: y ~ 1 + c & a + c & b

julia> Formula(StatsModels.Terms(y ~ 1 + (a+b) * c))
Formula: y ~ 1 + a + b + c + c & a + c & b
```

## The `ModelFrame` and `ModelMatrix` types

The main use of `Formula`s is for fitting statistical models based on tabular
data.  From the user's perspective, this is done by `fit` methods that take a
`Formula` and a `DataFrame` instead of numeric matrices.

Internally, this is accomplished in three stages:

1. The `Formula` is parsed into `Terms`.
2. The `Terms` and the data source are wrapped in a `ModelFrame`.
3. A numeric `ModelMatrix` is generated from the `ModelFrame` and passed to the
   model's `fit` method.

```@docs
ModelFrame
ModelMatrix
Terms
```
