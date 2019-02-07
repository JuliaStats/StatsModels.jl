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

```@repl 1
using StatsModels; # hide
dump(Term(:a) & Term(:b))
dump(Term(:a) + Term(:b))
dump(Term(:y) ~ Term(:a))
```

!!! note
    
    As always, you can introspect which method is called with

    ```julia
    julia> @which Term(:a) & Term(:b)
    &(terms::AbstractTerm...) in StatsModels at /home/dave/.julia/dev/StatsModels/src/terms.jl:224
    ```

The reason that the actual construction of higher-order terms is done after the
macro is expanded is that it makes it much easier to create a formula
programatically:

```@repl 1
f = Term(:y) ~ sum(Term(s) for s in [:a, :b, :c])
f == @formula(y ~ a + b + c)
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

```@repl 1
using DataFrames    # for pretty printing---any Table will do
df = DataFrame(y = rand(9), a = [1:9;], b = rand(9), c = repeat(["a","b","c"], 3))
schema(df)
```

However, if a term (including a `FormulaTerm`) is provided, the schema will be
computed based only on the necessary variables:

```@repl 1
schema(@formula(y ~ 1 + a), df)
schema(Term(:a) + Term(:b), df)
```

Once a schema is computed, it's _applied_ to the formula with
[`apply_schema`](@ref).  Among other things, this _instantiates_ placeholder
terms: 
* `Term`s become `ContinuousTerm`s or `CategoricalTerm`s
* `ConstantTerm`s become `InterceptTerm`s
* Tuples of terms [`MatrixTerm`](@ref)s where appropriate to explicitly indicate
  they should be concatenated into a single model matrix

```@repl 1
f = @formula(y ~ 1 + a + b + c)
typeof(f)
f = apply_schema(f, schema(f, df))
typeof(f)
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
time".  The main API method is [`model_cols`](@ref), which when applied to a
`FormulaTerm` returns a tuple of the numeric forms for the left- (response) and
right-hand (predictor) sides.

```@repl 1
response, predictors = model_cols(f, df);
response
predictors
```

`model_cols` can also take a single row from a table, as a `NamedTuple`:

```@repl 1
using Tables
model_cols(f, first(Tables.rowtable(df)))
```

Any `AbstractTerm` can be passed to `model_cols` with a table, which returns one or
more numeric arrays:



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

function StatsModels.model_cols(p::PolyTerm, d::NamedTuple)
    col = model_cols(p.term, d)
    reduce(hcat, (col.^n for n in 1:p.deg))
end

StatsBase.coefnames(p::PolyTerm) = coefnames(p.term) .* "^" .* string.(1:p.deg)
```

Now, we can use `poly` in a formula:

```@repl 1
data = DataFrame(y = rand(4), a = rand(4), b = [1:4;])
f = @formula(y ~ 1 + poly(b, 2) * a)
f = apply_schema(f, schema(data))
model_cols(f.rhs, data)
coefnames(f.rhs)
```

It's also possible to _block_ interpretation of the `poly` syntax as special in
certain contexts by adding additional (more specific) methods.  For instance, we
could block for the default model context of `Nothing`:

```@example 1
StatsModels.apply_schema(t::FunctionTerm{typeof(poly)}, sch, Mod::Type{Nothing}) = t
```

Now the `poly` is interpreted by default as the "vanilla" function defined
first, which just raises its first argument to the designated power:

```@repl 1
f = apply_schema(@formula(y ~ 1 + poly(b,2) * a), schema(data))
model_cols(f.rhs, data)
coefnames(f.rhs)
```

But by using a different context (e.g., `StatisticalModel`) we get the custom
interpretation:

```@repl 1
f2 = apply_schema(@formula(y ~ 1 + poly(b,2) * a), schema(data), StatisticalModel)
model_cols(f2.rhs, data)
coefnames(f2.rhs)
```

### Summary

"Custom syntax" means that calls to a particular function in a formula are not
interpreted as normal Julia code, but rather as a particular (possibly special)
kind of term.

Custom syntax is a combination of **syntax** (Julia function) and **term** (subtype
of `AbstractTerm`).  This syntax applies in a particular **context** (schema
plus model type, designated via a method of [`apply_schema`](@ref)),
transforming a `FunctionTerm{syntax}` into another (often custom) term type.
This custom term type then specifies special **behavior** at data time (via a
method for [`model_cols`](@ref)).

Finally, note that it's easy for a package to intercept the formula terms and
manipulate them directly as well, before calling `apply_schema` or
`model_cols`.  This gives packages great flexibility in how they interpret
formula terms.
