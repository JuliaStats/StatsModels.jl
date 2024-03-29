```@meta
DocTestSetup = quote
    using StatsModels
end
DocTestFilters = [r"([a-z]*) => \1"]
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

1. "Syntax time" when only the surface syntax is available, when the `@formula`
   macro is invoked.
2. "Schema time" incorporates information about **data invariants** (types of
   each variable, levels of categorical variables, summary statistics for
   continuous variables) and the overall structure of the **data**, during the
   invocation of `schema`.
3. "Semantics time" incorporates information about the **model type (context)**,
   and custom terms, during the call to `apply_schema`.
4. "Data time" when the actual data values themselves are available.

For in-memory (columnar) tables, there is not much difference between "data
time" and "schema time" in practice, but in principle it's important to
distinguish between these when dealing with truly streaming data, or large data
stores where calculating invariants of the data may be expensive.

### Syntax time (`@formula`)

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
InteractionTerm{Tuple{Term, Term}}
  terms: Tuple{Term, Term}
    1: Term
      sym: Symbol a
    2: Term
      sym: Symbol b

julia> dump(Term(:a) + Term(:b))
Tuple{Term, Term}
  1: Term
    sym: Symbol a
  2: Term
    sym: Symbol b

julia> dump(Term(:y) ~ Term(:a))
FormulaTerm{Term, Term}
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
programmatically:

```jldoctest 1
julia> f = Term(:y) ~ sum(term.([1, :a, :b, :c]))
FormulaTerm
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

Internally a lot of the work at syntax time is done by the `parse!` function.

### Schema time (`schema`)

The next phase of life for a formula requires some information about the data it
will be used with.  This is represented by a _schema_, a mapping from
placeholder `Term`s to _concrete_ terms—like `ContinuousTerm`
`CategoricalTerm`—which represent all the summary information about a data
column necessary to create a model matrix from that column.

There are a number of ways to construct a schema, ranging from fully automatic
to fully manual.

#### Fully automatic: `schema`

The most convenient way to automatically compute a schema is with the `schema`
function.  By default, it will create a schema for every column in the data:

```jldoctest 1
julia> using DataFrames    # for pretty printing---any Table will do

julia> using StableRNGs; rng = StableRNG(1);

julia> df = DataFrame(y = rand(rng, 9), a = 1:9, b = rand(rng, 9), c = repeat(["a","b","c"], 3))
9×4 DataFrame
 Row │ y          a      b         c
     │ Float64    Int64  Float64   String
─────┼────────────────────────────────────
   1 │ 0.585195       1  0.236782  a
   2 │ 0.0773379      2  0.943741  b
   3 │ 0.716628       3  0.445671  c
   4 │ 0.320357       4  0.763679  a
   5 │ 0.653093       5  0.145071  b
   6 │ 0.236639       6  0.021124  c
   7 │ 0.709684       7  0.152545  a
   8 │ 0.557787       8  0.617492  b
   9 │ 0.05079        9  0.481531  c

julia> schema(df)
StatsModels.Schema with 4 entries:
  y => y
  a => a
  b => b
  c => c
```

However, if a term (including a `FormulaTerm`) is provided, the schema will be
computed based only on the necessary variables:

```jldoctest 1
julia> schema(@formula(y ~ 1 + a), df)
StatsModels.Schema with 2 entries:
  y => y
  a => a

julia> schema(Term(:a) + Term(:b), df)
StatsModels.Schema with 2 entries:
  a => a
  b => b
```

#### Fully manual: term constructors

While `schema` is a convenient way to generate a schema automatically from a
data source, in some cases it may be preferable to create a schema manually.  In
particular, `schema` performs a complete sweep through the data, and if your
dataset is very large or truly streaming (online), then this may be
undesirable.  In such cases, you can construct a schema from instances of the
relevant concrete terms ([`ContinuousTerm`](@ref) or [`CategoricalTerm`](@ref)),
in a number of ways.

The constructors for concrete terms provide the maximum level of control.  A
`ContinuousTerm` stores values for the mean, standard deviation, minimum, and
maximum, while a `CategoricalTerm` stores the
[`StatsModels.ContrastsMatrix`](@ref) that defines the mapping from levels to
predictors, and these need to be manually supplied to the constructors:

!!! warning
    The format of the invariants stored in a term are implementation details and
    subject to change.

```jldoctest sch
julia> cont_a = ContinuousTerm(:a, 0., 1., -1., 1.)
a(continuous)

julia> cat_b = CategoricalTerm(:b, StatsModels.ContrastsMatrix(DummyCoding(), [:a, :b, :c]))
b(DummyCoding:3→2)
```

The `Term`-concrete term pairs can then be passed to the `StatsModels.Schema`
constructor (a wrapper for the underlying `Dict{Term,AbstractTerm}`):

```jldoctest sch
julia> sch1 = StatsModels.Schema(term(:a) => cont_a, term(:b) => cat_b)
StatsModels.Schema with 2 entries:
  a => a
  b => b
```

#### Semi-automatic: data subsets

A slightly more convenient method for generating a schema is provided by
the [`concrete_term`](@ref) internal function, which extracts invariants from a
data column and returns a concrete type.  This can be used to generate concrete
terms from data vectors constructed to have the same invariants that you care
about in your actual data (e.g., the same unique values for categorical data,
and the same minimum/maximum values or the same mean/variance for continuous):

```jldoctest
julia> cont_a2 = concrete_term(term(:a), [-1., 1.])
a(continuous)

julia> cat_b2 = concrete_term(term(:b), [:a, :b, :c])
b(DummyCoding:3→2)

julia> sch2 = StatsModels.Schema(term(:a) => cont_a2, term(:b) => cat_b2)
StatsModels.Schema with 2 entries:
  a => a
  b => b
```

Finally, you could also call `schema` on a `NamedTuple` of vectors (e.g., a
`Tables.ColumnTable`) with the necessary invariants:

```jldoctest
julia> sch3 = schema((a=[-1., 1], b=[:a, :b, :c]))
StatsModels.Schema with 2 entries:
  a => a
  b => b
```

### Semantics time (`apply_schema`)

The next stage of life for a formula happens when _semantic_ information is
available, which includes the schema of the data to be transformed as well as
the _context_, or the type of model that will be fit.  This stage is implemented
by [`apply_schema`](@ref).  Among other things, this _instantiates_ placeholder
terms:

* `Term`s become `ContinuousTerm`s or `CategoricalTerm`s
* `ConstantTerm`s become `InterceptTerm`s
* Tuples of terms become [`MatrixTerm`](@ref)s where appropriate to explicitly indicate
  they should be concatenated into a single model matrix
* Any model-specific (context-specific) interpretation of the terms is made, including
  transforming calls to functions that have special meaning in particular
  contexts into their special term types (see the section on [Extending
  `@formula` syntax](@ref extending) below)

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
FormulaTerm{Term, Tuple{ConstantTerm{Int64}, Term, Term, Term, InteractionTerm{Tuple{Term, Term}}}}

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
FormulaTerm{ContinuousTerm{Float64}, MatrixTerm{Tuple{InterceptTerm{true}, ContinuousTerm{Float64}, ContinuousTerm{Float64}, CategoricalTerm{DummyCoding, Matrix{Float64}, 2}, InteractionTerm{Tuple{ContinuousTerm{Float64}, CategoricalTerm{DummyCoding, Matrix{Float64}, 2}}}}}}
```

This transformation is done by calling `apply_schema(term, schema, modeltype)`
recursively on each term (the `modeltype` defaults to `StatisticalModel` when
fitting a statistical model, and `Nothing` if `apply_schema` is called with only
two arguments).  Because `apply_schema` dispatches on the term, schema, and
model type, this stage allows generic context-aware transformations, based on
_both_ the source (schema) _and_ the destination (model type).  This is the
primary mechanisms by which the formula DSL can be extended ([see
below](@ref extending) for more details)

### Data time (`modelcols`)

At the end of "schema time", a formula encapsulates all the information needed
to convert a table into a numeric model matrix.  That is, it is ready for "data
time".  The main API method is [`modelcols`](@ref), which when applied to a
`FormulaTerm` returns a tuple of the numeric forms for the left- (response) and
right-hand (predictor) sides.

```jldoctest 1
julia> resp, pred = modelcols(f, df);

julia> resp
9-element Vector{Float64}:
 0.5851946422124186
 0.07733793456911231
 0.7166282400543453
 0.3203570514066232
 0.6530930076222579
 0.2366391513734556
 0.7096838914472361
 0.5577872440804086
 0.05079002172175784

julia> pred
9×7 Matrix{Float64}:
 1.0  1.0  0.236782  0.0  0.0  0.0       0.0
 1.0  2.0  0.943741  1.0  0.0  0.943741  0.0
 1.0  3.0  0.445671  0.0  1.0  0.0       0.445671
 1.0  4.0  0.763679  0.0  0.0  0.0       0.0
 1.0  5.0  0.145071  1.0  0.0  0.145071  0.0
 1.0  6.0  0.021124  0.0  1.0  0.0       0.021124
 1.0  7.0  0.152545  0.0  0.0  0.0       0.0
 1.0  8.0  0.617492  1.0  0.0  0.617492  0.0
 1.0  9.0  0.481531  0.0  1.0  0.0       0.481531

```

`modelcols` can also take a single row from a table, as a `NamedTuple`:

```jldoctest 1
julia> using Tables

julia> modelcols(f, first(Tables.rowtable(df)))
(0.5851946422124186, [1.0, 1.0, 0.236781883208121, 0.0, 0.0, 0.0, 0.0])

```

Any `AbstractTerm` can be passed to `modelcols` with a table, which returns one or
more numeric arrays:

```jldoctest 1
julia> t = f.rhs.terms[end]
b(continuous) & c(DummyCoding:3→2)

julia> modelcols(t, df)
9×2 Matrix{Float64}:
 0.0       0.0
 0.943741  0.0
 0.0       0.445671
 0.0       0.0
 0.145071  0.0
 0.0       0.021124
 0.0       0.0
 0.617492  0.0
 0.0       0.481531

```


## [Extending `@formula` syntax](@id extending)

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

### An example of custom syntax: `poly`

As an example, we'll add syntax for specifying a [polynomial
regression](https://en.wikipedia.org/wiki/Polynomial_regression) model, which
fits a regression using polynomial basis functions of a continuous predictor.

The first step is to specify the **syntax** we're going to use.  While it's
possible to use an existing function, the best practice is to define a new
function to make dispatch less ambiguous.

```jldoctest 1
using StatsAPI
# syntax: best practice to define a _new_ function
poly(x, n) = x^n

# type of model where syntax applies: here this applies to any model type
const POLY_CONTEXT = Any

# struct for behavior
struct PolyTerm{T,D} <: AbstractTerm
    term::T
    deg::D
end

Base.show(io::IO, p::PolyTerm) = print(io, "poly($(p.term), $(p.deg))")

# for `poly` use at run-time (outside @formula), return a schema-less PolyTerm
poly(t::Symbol, d::Int) = PolyTerm(term(t), term(d))

# for `poly` use inside @formula: create a schemaless PolyTerm and apply_schema
function StatsModels.apply_schema(t::FunctionTerm{typeof(poly)},
                                  sch::StatsModels.Schema,
                                  Mod::Type{<:POLY_CONTEXT})
    apply_schema(PolyTerm(t.args...), sch, Mod)
end

# apply_schema to internal Terms and check for proper types
function StatsModels.apply_schema(t::PolyTerm,
                                  sch::StatsModels.Schema,
                                  Mod::Type{<:POLY_CONTEXT})
    term = apply_schema(t.term, sch, Mod)
    isa(term, ContinuousTerm) ||
        throw(ArgumentError("PolyTerm only works with continuous terms (got $term)"))
    isa(t.deg, ConstantTerm) ||
        throw(ArgumentError("PolyTerm degree must be a number (got $t.deg)"))
    PolyTerm(term, t.deg.n)
end

function StatsModels.modelcols(p::PolyTerm, d::NamedTuple)
    col = modelcols(p.term, d)
    reduce(hcat, [col.^n for n in 1:p.deg])
end

# the basic terms contained within a PolyTerm (for schema extraction)
StatsModels.terms(p::PolyTerm) = terms(p.term)
# names variables from the data that a PolyTerm relies on
StatsModels.termvars(p::PolyTerm) = StatsModels.termvars(p.term)
# number of columns in the matrix this term produces
StatsModels.width(p::PolyTerm) = p.deg

StatsAPI.coefnames(p::PolyTerm) = coefnames(p.term) .* "^" .* string.(1:p.deg)

# output


```

Now, we can use `poly` in a formula:

```jldoctest 1
julia> data = DataFrame(y = rand(rng, 4), a = rand(rng, 4), b = [1:4;])
4×3 DataFrame
 Row │ y         a         b
     │ Float64   Float64   Int64
─────┼───────────────────────────
   1 │ 0.752223  0.757746      1
   2 │ 0.314815  0.419294      2
   3 │ 0.858522  0.412607      3
   4 │ 0.698713  0.454589      4

julia> f = @formula(y ~ 1 + poly(b, 2) * a)
FormulaTerm
Response:
  y(unknown)
Predictors:
  1
  (b)->poly(b, 2)
  a(unknown)
  (b)->poly(b, 2) & a(unknown)

julia> f = apply_schema(f, schema(data))
FormulaTerm
Response:
  y(continuous)
Predictors:
  1
  poly(b, 2)
  a(continuous)
  poly(b, 2) & a(continuous)

julia> modelcols(f.rhs, data)
4×6 Matrix{Float64}:
 1.0  1.0   1.0  0.757746  0.757746  0.757746
 1.0  2.0   4.0  0.419294  0.838587  1.67717
 1.0  3.0   9.0  0.412607  1.23782   3.71347
 1.0  4.0  16.0  0.454589  1.81836   7.27343

julia> coefnames(f.rhs)
6-element Vector{String}:
 "(Intercept)"
 "b^1"
 "b^2"
 "a"
 "b^1 & a"
 "b^2 & a"

```

And in a linear regression, with simulated data where there is an effect of `a^1`
and of `b^2` (but not `a^2` or `b^1`):

```jldoctest 1
julia> using GLM

julia> sim_dat = DataFrame(a=rand(rng, 100).-0.5, b=randn(rng, 100).-0.5);

julia> sim_dat.y = randn(rng, 100) .+ 1 .+ 2*sim_dat.a .+ 3*sim_dat.b.^2;

julia> fit(LinearModel, @formula(y ~ 1 + poly(a,2) + poly(b,2)), sim_dat)
StatsModels.TableRegressionModel{LinearModel{GLM.LmResp{Vector{Float64}}, GLM.DensePredChol{Float64, LinearAlgebra.CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}}}, Matrix{Float64}}

y ~ 1 + poly(a, 2) + poly(b, 2)

Coefficients:
──────────────────────────────────────────────────────────────────────────
                 Coef.  Std. Error      t  Pr(>|t|)   Lower 95%  Upper 95%
──────────────────────────────────────────────────────────────────────────
(Intercept)   0.89288    0.181485    4.92    <1e-05   0.532586    1.25317
a^1           2.73324    0.349194    7.83    <1e-11   2.04001     3.42648
a^2          -1.0114     1.34262    -0.75    0.4531  -3.67684     1.65404
b^1           0.214424   0.136868    1.57    0.1205  -0.0572944   0.486142
b^2           3.15133    0.0811794  38.82    <1e-59   2.99016     3.31249
──────────────────────────────────────────────────────────────────────────
```

### [Making special syntax "runtime friendly"] (@id extend-runtime)

When used from the `@formula` macro, special syntax relies on dispatching on the
`FunctionTerm{MyFunction}` type.  But when creating a formula at runtime
without the `@formula` macro, `FunctionTerm`s aren't available, and so care must
be taken to make sure you provide a runtime replacement.  The example for `poly`
above shows how to do this, but we spell it out here in more detail.

The first step is to make sure you can create a schema-less instance of the
`AbstractTerm` that implements your special syntax behavior.  For the
`poly` example, that means we need to be able to create a
`PolyTerm(term(column_name), term(poly_degree))`.  In order to do this, the
types of the `term` and `deg` fields aren't specified but are parameters of the
`PolyTerm` type.

The second step is to provide a runtime method for the special syntax function
(`poly`), which accepts arguments in form that's convenient at runtime.  For
this example, we've defined `poly(s::Symbol, i::Int) = PolyTerm(term(s),
term(i))`:

```jldoctest 1
julia> pt = poly(:a, 3)
poly(a, 3)

julia> typeof(pt) # contains schema-less `Term`
PolyTerm{Term, ConstantTerm{Int64}}
```

!!! note

    The functions like `poly` should be exported by the package that provides
    the special syntax for two reasons.  First, it makes run-time term
    construction more convenient.  Second, because of how the `@formula` macro
    generates code, the function that represents special syntax must be
    available in the namespace where `@formula` is _called_.  This is because
    calls to arbitrary functions `f` are lowered to `FunctionTerm{typeof(f)}`.

Now we can programmatically construct `PolyTerm`s at run-time:

```jldoctest 1
julia> my_col = :a; my_degree = 3;

julia> poly(my_col, my_degree)
poly(a, 3)

julia> poly.([:a, :b], my_degree)
2-element Vector{PolyTerm{Term, ConstantTerm{Int64}}}:
 poly(a, 3)
 poly(b, 3)
```

These run-time `PolyTerm`s are "schema-less" though, and to be able to construct
a model matrix from them we need to have a way to apply a schema.  Thus, the
third and final step is to provide an `apply_schema` method that upgrades a
schema-less instance to one with a schema (i.e., one that can be used with
`modelcols`).  For example, we've specified `apply_schema(pt::PolyTerm, ...)`
which calls `apply_schema` on the wrapped `pt.term`, returning a new `PolyTerm`
with the instantiated result:

```jldoctest 1
julia> pt = apply_schema(PolyTerm(term(:b), term(2)),
                         schema(data),
                         StatisticalModel)
poly(b, 2)

julia> typeof(pt) # now holds a `ContinuousTerm`
PolyTerm{ContinuousTerm{Float64}, Int64}

julia> modelcols(pt, data)
4×2 Matrix{Int64}:
 1   1
 2   4
 3   9
 4  16
```

Now with these methods in place, we can run exactly the same polynomial
regression as above (which used `@formula(y ~ 1 + poly(a, 2) + poly(b, 2)`), but
with the predictor names and the polynomial degree stored in variables:

```jldoctest 1
julia> poly_vars = (:a, :b); poly_deg = 2;

julia> poly_formula = term(:y) ~ term(1) + poly.(poly_vars, poly_deg)
FormulaTerm
Response:
  y(unknown)
Predictors:
  1
  poly(a, 2)
  poly(b, 2)

julia> fit(LinearModel, poly_formula, sim_dat)
StatsModels.TableRegressionModel{LinearModel{GLM.LmResp{Vector{Float64}}, GLM.DensePredChol{Float64, LinearAlgebra.CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}}}, Matrix{Float64}}

y ~ 1 + poly(a, 2) + poly(b, 2)

Coefficients:
──────────────────────────────────────────────────────────────────────────
                 Coef.  Std. Error      t  Pr(>|t|)   Lower 95%  Upper 95%
──────────────────────────────────────────────────────────────────────────
(Intercept)   0.89288    0.181485    4.92    <1e-05   0.532586    1.25317
a^1           2.73324    0.349194    7.83    <1e-11   2.04001     3.42648
a^2          -1.0114     1.34262    -0.75    0.4531  -3.67684     1.65404
b^1           0.214424   0.136868    1.57    0.1205  -0.0572944   0.486142
b^2           3.15133    0.0811794  38.82    <1e-59   2.99016     3.31249
──────────────────────────────────────────────────────────────────────────
```

### Defining the context where special syntax applies

The third argument to `apply_schema` determines the contexts in which the
special `poly` syntax applies.

For instance, it's possible to _block_ interpretation of the `poly` syntax as
special in certain contexts by adding additional (more specific) methods.  If
for some reason we wanted to block `PolyTerm`s being generated for
`GLM.LinearModel`, then we just need to add the appropriate method:

```jldoctest 1
julia> StatsModels.apply_schema(t::FunctionTerm{typeof(poly)},
                                sch::StatsModels.Schema,
                                Mod::Type{GLM.LinearModel}) = t
```

Now in the context of a `LinearModel`, the `poly` is interpreted as a call to
the "vanilla" function defined first, which just raises its first argument to
the designated power:

```jldoctest 1
julia> f = apply_schema(@formula(y ~ 1 + poly(b,2) * a),
                        schema(data),
                        GLM.LinearModel)
FormulaTerm
Response:
  y(continuous)
Predictors:
  1
  (b)->poly(b, 2)
  a(continuous)
  (b)->poly(b, 2) & a(continuous)

julia> modelcols(f.rhs, data)
4×4 Matrix{Float64}:
 1.0   1.0  0.757746  0.757746
 1.0   4.0  0.419294  1.67717
 1.0   9.0  0.412607  3.71347
 1.0  16.0  0.454589  7.27343

julia> coefnames(f.rhs)
4-element Vector{String}:
 "(Intercept)"
 "poly(b, 2)"
 "a"
 "poly(b, 2) & a"

```

But by using a different context (e.g., the related but more general
`GLM.GeneralizedLinearModel`) we get the custom interpretation:

```jldoctest 1
julia> f2 = apply_schema(@formula(y ~ 1 + poly(b,2) * a),
                         schema(data),
                         GLM.GeneralizedLinearModel)
FormulaTerm
Response:
  y(continuous)
Predictors:
  1
  poly(b, 2)
  a(continuous)
  poly(b, 2) & a(continuous)

julia> modelcols(f2.rhs, data)
4×6 Matrix{Float64}:
 1.0  1.0   1.0  0.757746  0.757746  0.757746
 1.0  2.0   4.0  0.419294  0.838587  1.67717
 1.0  3.0   9.0  0.412607  1.23782   3.71347
 1.0  4.0  16.0  0.454589  1.81836   7.27343

julia> coefnames(f2.rhs)
6-element Vector{String}:
 "(Intercept)"
 "b^1"
 "b^2"
 "a"
 "b^1 & a"
 "b^2 & a"
```

The definitions of these methods control how models of each type are _fit_ from
a formula with a call to `poly`:

```jldoctest 1
julia> sim_dat = DataFrame(b=randn(rng, 100));

julia> sim_dat.y = randn(rng, 100) .+ 1 .+ 2*sim_dat.b .+ 3*sim_dat.b.^2;

julia> fit(LinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat)
StatsModels.TableRegressionModel{LinearModel{GLM.LmResp{Vector{Float64}}, GLM.DensePredChol{Float64, LinearAlgebra.CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}}}, Matrix{Float64}}

y ~ 1 + :(poly(b, 2))

Coefficients:
───────────────────────────────────────────────────────────────────────
               Coef.  Std. Error      t  Pr(>|t|)  Lower 95%  Upper 95%
───────────────────────────────────────────────────────────────────────
(Intercept)  1.28118    0.324615   3.95    0.0001   0.636991    1.92537
poly(b, 2)   2.95861    0.174347  16.97    <1e-30   2.61262     3.30459
───────────────────────────────────────────────────────────────────────

julia> fit(GeneralizedLinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat, Normal())
StatsModels.TableRegressionModel{GeneralizedLinearModel{GLM.GlmResp{Vector{Float64}, Normal{Float64}, IdentityLink}, GLM.DensePredChol{Float64, LinearAlgebra.CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}}}, Matrix{Float64}}

y ~ 1 + poly(b, 2)

Coefficients:
────────────────────────────────────────────────────────────────────────
                Coef.  Std. Error      z  Pr(>|z|)  Lower 95%  Upper 95%
────────────────────────────────────────────────────────────────────────
(Intercept)  0.906356   0.132613    6.83    <1e-11    0.64644    1.16627
b^1          2.03194    0.0908937  22.36    <1e-99    1.85379    2.21008
b^2          3.02886    0.0707228  42.83    <1e-99    2.89025    3.16748
────────────────────────────────────────────────────────────────────────

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
