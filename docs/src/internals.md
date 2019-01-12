# Internals and extending the formula DSL

The Julia `@formula` is designed to be as extensible as possible through the
normal Julian mechanisms of multiple dispatch.





## The lifecycle of a `@formula`

A formula goes through a number of stages, starting as an
expression that's passed to the `@formula` macro and ending up generating a
numeric matrix when ultimately combined with a tabular data source:

1. "Macro time" when only the surface syntax is available
2. "Schema time" incorporates information about **data invariants** (types of each
   variable, levels of categorical variables, summary statistics for continuous
   variables) and the **model type**.
3. "Data time" when the actual data values themselves are available.

For in-memory (columnar) tables, there is not much difference between "data
time" and "schema time" in practice, but in principle it's important to
distinguish between these when dealing with truly streaming data, or large data
stores where calculating invariants of the data may be expensive.

### Macro time

The `@formula` macro does syntactic transformations of the formula expression.
At this point, _only_ the expression itself is available, and there's no way to
know whether a term corresponds to a continuous or categorical variable.

For standard formulae, this amounts to applying the syntactic rules for the DSL
operators (expanding `*` and applying the distributive and associative rules),
and wrapping each symbol in a `Term` constructor:

```julia
julia> @macroexpand @formula(y ~ 1 + a*b)
:(Term(:y) ~ ConstantTerm(1) + Term(:a) + Term(:b) + Term(:a) & Term(:b))
```

Calling this stage "macro time" is a bit of a misnormer because much of the
action happens when the expression returned by the `@formula` macro is
evaluated.  At this point, the `Term`s are combined to create higher-order terms
via overloaded methods for `~`, `+`, and `&`:

```julia
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
    &(terms::AbstractTerm...) in StatsModels at /home/dave/.julia/dev/StatsModels/src/terms.jl:224
    ```

The reason that the actual construction of higher-order terms is done after the
macro is expanded is that it makes it much easier to create a formula
programatically:

```julia
julia> f = Term(:y) ~ sum(Term(s) for s in [:a, :b, :c])
y ~ a + b + c

julia> f == @formula(y ~ a + b + c)
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

```julia
julia> schema(df)
Dict{Any,Any} with 4 entries:
  b => b (continuous)
  a => a (continuous)
  c => c (3 levels): DummyCoding(2)
  y => y (continuous)
```

However, if a term (including a `FormulaTerm`) is provided, the schema will be
computed based only on the necessary variables:

```julia
julia> schema(@formula(y ~ 1 + a), df)
Dict{Any,Any} with 2 entries:
  a => a (continuous)
  y => y (continuous)

julia> schema(Term(:a) + Term(:b), df)
Dict{Any,Any} with 2 entries:
  b => b (continuous)
  a => a (continuous)
```

Once a schema is computed, it's _applied_ to the formula with `apply_schema`.
This converts each placeholder `Term` into a `ContinuousTerm` or
`CategoricalTerm`.  This is done by calling `apply_schema(term, schema,
ModelType)` recursively on each term.  Dispatching on the term, schema, and
model type allows for package authors to override default behavior for model
types they define or even adding extensions to the `@formula` DSL by dispatching
on `::FunctionTerm{F}` ([see below](#Extending-@formula-syntax-1) for more
details)

### Data time

At the end of "schema time", a formula encapsulates all the information needed
to convert a table into a numeric model matrix.  That is, it is ready for "data
time".  The main API method is `model_cols`:


Any `AbstractTerm` can be passed to `model_cols` with a table and returns one or
more numeric arrays:

```julia
julia> df = DataFrame(y = rand(9), a = [1:9;], b = rand(9), c = repeat(["a","b","c"], 3));

julia> 
```


## Extending `@formula` syntax

Package authors may want to create additional syntax to the `@formula` DSL so
their users can conveniently specify particular kinds of models.  StatsModels.jl
provides mechanisms for such extensions that do _not_ rely on compile time
"macro magic", but on standard julian mechanisms of multiple dispatch.

Extensions have three components:
1. **Syntax**: the julia function which is given special meaning inside a formula.
2. **Context**: the model type(s) where this extension applies
3. **Behavior**: how tabular data bis transformed under this extension

### Example

As an example, we'll add syntax for specifying a [polynomial
regression](https://en.wikipedia.org/wiki/Polynomial_regression) model, which
fits a regression using polynomial basis functions of a continuous predictor.

The first step is to specify the **syntax** we're going to use.  While it's
possible to use an existing function, the best practice is to define a new
function to make dispatch less ambiguous.

```julia
# syntax: best practice to define a _new_ function
poly(x, n) = x^n

# type of model where syntax applies
const POLY_CONTEXT = Any

# struct for behavior
struct PolyTerm <: AbstractTerm
    term::ContinuousTerm
    deg::Int
end
PolyTerm(t::ContinuousTerm, deg::ConstantTerm) = PolyTerm(t, deg.n)


function apply_schema(t::FunctionTerm{typeof(poly)}, sch, Mod::Type{POLY_CONTEXT})
    PolyTerm(apply_schema(t.args_parsed[1], sch, Mod
end
    PolyTerm(apply_schema(t.args_parsed...)

StatsModels.model_cols(p::PolyTerm, d::NamedTuple) =
    reduce(hcat, (d[p.term].^n for n in 1:p.deg))

```

### Summary

"Custom syntax" means that calls to a particular function in a formula are
not interpreted as normal julia code, but rather as a particular kind of term.

Custom syntax is a combination of **syntax** (julia function) and **term**
(subtype of `AbstractTerm`)p

The standard way to extend the `@formula` DSL is to create a custom
`AbstractTerm`.


