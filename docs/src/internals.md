```@meta
DocTestSetup = quote
    using StatsModels
    using Random
    Random.seed!(1)
end
```

# Internals and extending the formula DSL

This section is intended to help **package developers** understand the internals
of how a `@formula` becomes a numerical matrix, in order to use, manipulate, and
even extend the DSL.  The Julia `@formula` is designed to be as extensible as
possible through the normal Julian mechanisms of multiple dispatch.

## The lifecycle of a `@formula`

A formula goes through a number of stages, starting as an
expression that's passed to the `@formula` macro and ending up generating a
numeric matrix when ultimately combined with a tabular data source:

1. "Syntax time" when only the surface syntax is available
2. "Schema time" incorporates information about **data invariants** (types of each
   variable, levels of categorical variables, summary statistics for continuous
   variables) and the **model type**.
3. "Data time" when the actual data values themselves are available.

For in-memory (columnar) tables, there is not much difference between "data
time" and "schema time" in practice, but in principle it's important to
distinguish between these when dealing with truly streaming data, or large data
stores where calculating invariants of the data may be expensive.

### Syntax time

The `@formula` macro does syntactic transformations of the formula expression.
At this point, _only_ the expression itself is available, and there's no way to
know whether a term corresponds to a continuous or categorical variable.

For standard formulae, this amounts to applying the syntactic rules for the DSL
operators (expanding `*` and applying the distributive and associative rules),
and wrapping each symbol in a `Term` constructor:

```julia-repl
julia> @macroexpand @formula(y ~ 1 + a*b)
:(Term(:y) ~ ConstantTerm(1) + Term(:a) + Term(:b) + Term(:a) & Term(:b))
```

Note that much of the action happens _outside_ the `@formula` macro, when the
expression returned by the `@formula` macro is evaluated.  At this point, the
`Term`s are combined to create higher-order terms via overloaded methods for
`~`, `+`, and `&`:

```jldoctest 1
julia> using StatsModels;

julia> dump(Term(:a) & Term(:b))
InteractionTerm{Tuple{Term,Term}}
  terms: Tuple{Term,Term}
    1: Term
      sym: Symbol a
    2: Term
      sym: Symbol b

julia> dump(Term(:a) + Term(:b))
Tuple{Term,Term}
  1: Term
    sym: Symbol a
  2: Term
    sym: Symbol b

julia> dump(Term(:y) ~ Term(:a))
FormulaTerm{Term,Term}
  lhs: Term
    sym: Symbol y
  rhs: Term
    sym: Symbol a
```

!!! note
    
    As always, you can introspect which method is called with

    ```julia
    julia> @which Term(:a) & Term(:b)
    &(terms::AbstractTerm...) in StatsModels at /home/dave/.julia/dev/StatsModels/src/terms.jl:399
    ```

The reason that the actual construction of higher-order terms is done after the
macro is expanded is that it makes it much easier to create a formula
programatically:

```jldoctest 1
julia> f = Term(:y) ~ sum(term.([1, :a, :b, :c]))
Response:
  y(unknown)
Predictors:
  1
  a(unknown)
  b(unknown)
  c(unknown)

julia> f == @formula(y ~ 1 + a + b + c)
true
```

The major exception to this is that non-DSL calls **must** be specified using
the `@formula` macro.  The reason for this is that non-DSL calls are "captured"
and turned into anonymous functions that can be evaluated elementwise, which has
to happen at compile time.  For instance, the call to `log` in `@formula(y ~
log(a+b))` is converted into the anonymous function `(a,b) -> log(a+b)`.

### Schema time

The next phase of life for a formula begins when a _schema_ for the data becomes
available.  A schema is a mapping from data columns to a concrete term
type---either a `ContinuousTerm` or a `CategoricalTerm`---which represents all
the summary information about a data column necessary to create a model matrix
from that column.

A schema is computed with the `schema` function.  By default, it will create a
schema for every column in the data:

```jldoctest 1
julia> using DataFrames    # for pretty printing---any Table will do

julia> df = DataFrame(y = rand(9), a = 1:9, b = rand(9), c = repeat(["a","b","c"], 3))
9×4 DataFrame
│ Row │ y          │ a     │ b        │ c      │
│     │ Float64    │ Int64 │ Float64  │ String │
├─────┼────────────┼───────┼──────────┼────────┤
│ 1   │ 0.186771   │ 1     │ 0.283518 │ a      │
│ 2   │ 0.30541    │ 2     │ 0.334256 │ b      │
│ 3   │ 0.737966   │ 3     │ 0.85574  │ c      │
│ 4   │ 0.772443   │ 4     │ 0.06847  │ a      │
│ 5   │ 0.80497    │ 5     │ 0.13961  │ b      │
│ 6   │ 0.902381   │ 6     │ 0.612018 │ c      │
│ 7   │ 0.00567164 │ 7     │ 0.663847 │ a      │
│ 8   │ 0.94135    │ 8     │ 0.923554 │ b      │
│ 9   │ 0.860734   │ 9     │ 0.402647 │ c      │

julia> schema(df)
Dict{Any,Any} with 4 entries:
  y => y
  a => a
  b => b
  c => c
```

However, if a term (including a `FormulaTerm`) is provided, the schema will be
computed based only on the necessary variables:

```jldoctest 1
julia> schema(@formula(y ~ 1 + a), df)
Dict{Any,Any} with 2 entries:
  y => y
  a => a

julia> schema(Term(:a) + Term(:b), df)
Dict{Any,Any} with 2 entries:
  a => a
  b => b
```

Once a schema is computed, it's _applied_ to the formula with
[`apply_schema`](@ref).  Among other things, this _instantiates_ placeholder
terms:
* `Term`s become `ContinuousTerm`s or `CategoricalTerm`s
* `ConstantTerm`s become `InterceptTerm`s
* Tuples of terms become [`MatrixTerm`](@ref)s where appropriate to explicitly indicate
  they should be concatenated into a single model matrix

```jldoctest 1
julia> f = @formula(y ~ 1 + a + b * c)
FormulaTerm
Response:
  y(unknown)
Predictors:
  1
  a(unknown)
  b(unknown)
  c(unknown)
  b(unknown) & c(unknown)

julia> typeof(f)
FormulaTerm{Term,Tuple{ConstantTerm{Int64},Term,Term,Term,InteractionTerm{Tuple{Term,Term}}}}

julia> f = apply_schema(f, schema(f, df))
FormulaTerm
Response:
  y(continuous)
Predictors:
  1
  a(continuous)
  b(continuous)
  c(DummyCoding:3→2)
  b(continuous) & c(DummyCoding:3→2)

julia> typeof(f)
FormulaTerm{ContinuousTerm{Float64},MatrixTerm{Tuple{InterceptTerm{true},ContinuousTerm{Float64},ContinuousTerm{Float64},CategoricalTerm{DummyCoding,String,2},InteractionTerm{Tuple{ContinuousTerm{Float64},CategoricalTerm{DummyCoding,String,2}}}}}}
```

This transformation is done by calling `apply_schema(term, schema, modeltype)`
recursively on each term (the `modeltype` defaults to `StatisticalModel` when
fitting a statistical model, and `Nothing` if `apply_schema` is called with only
two arguments).  Because `apply_schema` dispatches on the term, schema, and
model type, this stage allows generic context-aware transformations, based on
_both_ the source (schema) _and_ the destination (model type).  This is the
primary mechanisms by which the formula DSL can be extended ([see
below](#Extending-@formula-syntax-1) for more details)

### Data time

At the end of "schema time", a formula encapsulates all the information needed
to convert a table into a numeric model matrix.  That is, it is ready for "data
time".  The main API method is [`modelcols`](@ref), which when applied to a
`FormulaTerm` returns a tuple of the numeric forms for the left- (response) and
right-hand (predictor) sides.

```jldoctest 1
julia> resp, pred = modelcols(f, df);

julia> resp

julia> pred

```

`modelcols` can also take a single row from a table, as a `NamedTuple`:

```jldoctest 1
julia> using Tables

julia> modelcols(f, first(Tables.rowtable(df)))

```

Any `AbstractTerm` can be passed to `modelcols` with a table, which returns one or
more numeric arrays:

```jldoctest 1
julia> t = f.rhs.terms[end]

julia> modelcols(t, df)

```


## Extending `@formula` syntax

Package authors may want to create additional syntax to the `@formula` DSL so
their users can conveniently specify particular kinds of models.  StatsModels.jl
provides mechanisms for such extensions that do _not_ rely on compile time
"macro magic", but on standard julian mechanisms of multiple dispatch.

Extensions have three components:
1. **Syntax**: the Julia function which is given special meaning inside a formula.
2. **Context**: the model type(s) where this extension applies
3. **Behavior**: how tabular data is transformed under this extension

These correspond to the stages summarized above (syntax time, schema time, and
data time)

As an example, we'll add syntax for specifying a [polynomial
regression](https://en.wikipedia.org/wiki/Polynomial_regression) model, which
fits a regression using polynomial basis functions of a continuous predictor.

The first step is to specify the **syntax** we're going to use.  While it's
possible to use an existing function, the best practice is to define a new
function to make dispatch less ambiguous.

```@example 1
using StatsBase
# syntax: best practice to define a _new_ function
poly(x, n) = x^n

# type of model where syntax applies: here this applies to any model type
const POLY_CONTEXT = Any

# struct for behavior
struct PolyTerm <: AbstractTerm
    term::ContinuousTerm
    deg::Int
end

Base.show(io::IO, p::PolyTerm) = print(io, "poly($(p.term), $(p.deg))")

function StatsModels.apply_schema(t::FunctionTerm{typeof(poly)}, sch, Mod::Type{<:POLY_CONTEXT})
    term = apply_schema(t.args_parsed[1], sch, Mod)
    isa(term, ContinuousTerm) ||
        throw(ArgumentError("PolyTerm only works with continuous terms (got $term)"))
    deg = t.args_parsed[2]
    isa(deg, ConstantTerm) ||
        throw(ArgumentError("PolyTerm degree must be a number (got $deg)"))
    PolyTerm(term, deg.n)
end

function StatsModels.modelcols(p::PolyTerm, d::NamedTuple)
    col = modelcols(p.term, d)
    reduce(hcat, [col.^n for n in 1:p.deg])
end

StatsModels.width(p::PolyTerm) = p.deg

StatsBase.coefnames(p::PolyTerm) = coefnames(p.term) .* "^" .* string.(1:p.deg)
```

Now, we can use `poly` in a formula:

```jldoctest 1
julia> data = DataFrame(y = rand(4), a = rand(4), b = [1:4;])

julia> f = @formula(y ~ 1 + poly(b, 2) * a)

julia> f = apply_schema(f, schema(data))

julia> modelcols(f.rhs, data)

julia> coefnames(f.rhs)

```

It's also possible to _block_ interpretation of the `poly` syntax as special in
certain contexts by adding additional (more specific) methods.  For instance, we
could block `PolyTerm`s being generated for `GLM.LinearModel`:

```@example 1
using GLM
StatsModels.apply_schema(t::FunctionTerm{typeof(poly)},
                         sch,
                         Mod::Type{GLM.LinearModel}) = t
```

Now the `poly` is interpreted by default as the "vanilla" function defined
first, which just raises its first argument to the designated power:

```jldoctest 1
julia> f = apply_schema(@formula(y ~ 1 + poly(b,2) * a),
                        schema(data),
                        GLM.LinearModel)

julia> modelcols(f.rhs, data)

julia> coefnames(f.rhs)

```

But by using a different context (e.g., the more related but more general
`GLM.GeneralizedLinearModel`) we get the custom interpretation:

```jldoctest 1
julia> f2 = apply_schema(@formula(y ~ 1 + poly(b,2) * a),
                         schema(data),
                         GLM.GeneralizedLinearModel)

julia> modelcols(f2.rhs, data)

julia> coefnames(f2.rhs)
```

The definitions of these methods control how models of each type are _fit_ from
a formula with a call to `poly`:

```@repl 1
julia> sim_dat = DataFrame(b=randn(100));

julia> sim_dat[:y] = randn(100) .+ 1 .+ 2*sim_dat[:b] .+ 3*sim_dat[:b].^2;

julia> fit(LinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat)

julia> fit(GeneralizedLinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat,
Normal())

```

(a `GeneralizeLinearModel` with a `Normal` distribution is equivalent to a
`LinearModel`)

### Summary

"Custom syntax" means that calls to a particular function in a formula are not
interpreted as normal Julia code, but rather as a particular (possibly special)
kind of term.

Custom syntax is a combination of **syntax** (Julia function) and **term** (subtype
of `AbstractTerm`).  This syntax applies in a particular **context** (schema
plus model type, designated via a method of [`apply_schema`](@ref)),
transforming a `FunctionTerm{syntax}` into another (often custom) term type.
This custom term type then specifies special **behavior** at data time (via a
method for [`modelcols`](@ref)).

Finally, note that it's easy for a package to intercept the formula terms and
manipulate them directly as well, before calling `apply_schema` or
`modelcols`.  This gives packages great flexibility in how they interpret
formula terms.
