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
Formula: y ~ 1 + a + b + c + a & b + a & c + b & c + &(a, b, c)
```

Both the `*` and the `&` operators act like multiplication, and are distributive
over addition:

```jldoctest
julia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) & c)))
Formula: y ~ 1 + a & c + b & c

julia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) * c)))
Formula: y ~ 1 + a + b + c + a & c + b & c
```

### Constructing a formula programmatically

Because a `Formula` is created at compile time with the `@formula` macro,
creating one programmatically means dipping into Julia's
[metaprogramming](https://docs.julialang.org/en/latest/manual/metaprogramming/)
facilities.

Let's say you have a variable `lhs`:

```jldoctest
julia> lhs = :y
:y
```

and you want to create a formula whose left-hand side is the _value_ of `lhs`,
as in

```jldoctest
julia> @formula(y ~ 1 + x)
Formula: y ~ 1 + x
```

Simply using the Julia interpolation syntax `@formula($lhs ~ 1 + x)` won't work,
because `@formula` runs _at compile time_, before anything about the value of
`lhs` is known.  Instead, you need to construct and evaluate the _correct call_
to `@formula`.  The most concise way to do this is with `@eval`:

```jldoctest
julia> @eval @formula($lhs ~ 1 + x)
Formula: y ~ 1 + x
```

The `@eval` macro does two very different things in a single, convenient step:

1. Generate a _quoted expression_ using `$`-interpolation to insert the run-time
   value of `lhs` into the call to the `@formula` macro.
2. Evaluate this expression using `eval`.

An equivalent but slightly more verbose way of doing the same thing is:

```jldoctest
julia> formula_ex = :(@formula($lhs ~ 1 + x))
:(@formula y ~ 1 + x)

julia> eval(formula_ex)
Formula: y ~ 1 + x
```

### Technical details

You may be wondering why formulas in Julia require a macro, while in R they
appear "bare."  R supports nonstandard evaluation, allowing the formula to
remain an unevaluated object while its terms are parsed out. Julia uses a much
more standard evaluation mechanism, making this impossible using normal
expressions. However, unlike R, Julia provides macros to explicitly indicate
when code itself will be manipulated before it's evaluated. By constructing a
formula using a macro, we're able to provide convenient, R-like syntax and
semantics.

The formula syntactic transformations are applied _at parse time_ when using the
`@formula` macro.  You can see this with using `@macroexpand`:

```jldoctest
julia> @macroexpand @formula y ~ 1 + (a+b)*c
:((StatsModels.Formula)($(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + (a + b) * c)))))), $(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + a + b + c + a & c + b & c)))))), :y, $(Expr(:copyast, :($(QuoteNode(:(1 + a + b + c + a & c + b & c))))))))
```
Or more legibly
```julia
:((StatsModels.Formula)($(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + (a + b) * c)))))),
                        $(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + a + b + c + a & c + b & c)))))),
                        :y,
                        $(Expr(:copyast, :($(QuoteNode(:(1 + a + b + c + a & c + b & c))))))))
```

The `@formula` macro re-writes the formula expression `y ~ 1 + (a+b)*c` as a
call to the `Formula` constructor.  The arguments of the constructor correspond
to the fields of the `Formula` struct, which are, in order:

* `ex_orig`: the original expression `:(y ~ 1+(a+b)*c)`
* `ex`: the parsed expression `:(y ~ 1+a+b+a&c+b&c)`
* `lhs`: the left-hand side `:y`
* `rhs`: the right-hand side `:(1+a+b+a&c+b&c)`

```@docs
Formula
dropterm
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
