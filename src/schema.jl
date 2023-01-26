################################################################################
# Schemas for terms

# step 1: extract all Term symbols
# step 2: create empty Schema (Dict)
# step 3: for each term, create schema entry based on column from data store

# TODO: handle streaming (Data.RowTable) by iterating over rows and updating
# schemas in place

terms(t::FormulaTerm) = union(terms(t.lhs), terms(t.rhs))
terms(t::InteractionTerm) = terms(t.terms)
terms(t::FunctionTerm) = mapreduce(terms, union, t.args)
terms(t::AbstractTerm) = [t]
terms(t::MatrixTerm) = terms(t.terms)
terms(t::TupleTerm) = mapreduce(terms, union, t)

needs_schema(::AbstractTerm) = true
needs_schema(::ConstantTerm) = false
needs_schema(t) = false
# first possible fix for #97
needs_schema(::Union{CategoricalTerm, ContinuousTerm, InterceptTerm}) = false

"""
    StatsModels.Schema

Struct that wraps a `Dict` mapping `Term`s to their concrete forms.  This exists
mainly for dispatch purposes and to support possibly more sophisticated behavior
in the future.

A `Schema` behaves for all intents and purposes like an immutable `Dict`, and
delegates the constructor as well as `getindex`, `get`, `merge!`, `merge`,
`keys`, and `haskey` to the wrapped `Dict`.
"""
struct Schema
    schema::Dict{Term,AbstractTerm}
    Schema(x...) = new(Dict{Term,AbstractTerm}(x...))
end

Base.broadcastable(s::Schema) = Ref(s)

function Base.show(io::IO, schema::Schema)
    n = length(schema.schema)
    println(io, "StatsModels.Schema with $n ", n==1 ? "entry:" : "entries:")
    for (k,v) in schema.schema
        println(io, "  ", k, " => ", v)
    end
end

Base.getindex(schema::Schema, key) = getindex(schema.schema, key)
Base.get(schema::Schema, key, default) = get(schema.schema, key, default)
Base.merge(a::Schema, b::Schema) = Schema(merge(a.schema, b.schema))
Base.merge!(a::Schema, b::Schema) = (merge!(a.schema, b.schema); a)

Base.keys(schema::Schema) = keys(schema.schema)
Base.haskey(schema::Schema, key) = haskey(schema.schema, key)

"""
    schema([terms::AbstractVector{<:AbstractTerm}, ]data, hints::Dict{Symbol})
    schema(term::AbstractTerm, data, hints::Dict{Symbol})

Compute all the invariants necessary to fit a model with `terms`.  A schema is a dict that
maps `Term`s to their concrete instantiations (either `CategoricalTerm`s or
`ContinuousTerm`s.  "Hints" may optionally be supplied in the form of a `Dict` mapping term
names (as `Symbol`s) to term or contrast types.  If a hint is not provided for a variable,
the appropriate term type will be guessed based on the data type from the data column: any
numeric data is assumed to be continuous, and any non-numeric data is assumed to be
categorical.

Returns a [`StatsModels.Schema`](@ref), which is a wrapper around a `Dict`
mapping `Term`s to their concrete instantiations (`ContinuousTerm` or
`CategoricalTerm`).

# Example

```jldoctest 1
julia> using StableRNGs; rng = StableRNG(1);

julia> d = (x=sample(rng, [:a, :b, :c], 10), y=rand(rng, 10));

julia> ts = [Term(:x), Term(:y)];

julia> schema(ts, d)
StatsModels.Schema with 2 entries:
  x => x
  y => y

julia> schema(ts, d, Dict(:x => HelmertCoding()))
StatsModels.Schema with 2 entries:
  x => x
  y => y

julia> schema(term(:y), d, Dict(:y => CategoricalTerm))
StatsModels.Schema with 1 entry:
  y => y
```

Note that concrete `ContinuousTerm` and `CategoricalTerm` and un-typed `Term`s print the
same in a container, but when printed alone are different:

```jldoctest 1
julia> sch = schema(ts, d)
StatsModels.Schema with 2 entries:
  x => x
  y => y

julia> term(:x)
x(unknown)

julia> sch[term(:x)]
x(DummyCoding:3→2)

julia> sch[term(:y)]
y(continuous)
```
"""
schema(data, hints=Dict{Symbol,Any}()) = schema(columntable(data), hints)
schema(dt::D, hints=Dict{Symbol,Any}()) where {D<:ColumnTable} =
    schema(Term.(collect(fieldnames(D))), dt, hints)
schema(ts::AbstractVector{<:AbstractTerm}, data, hints::Dict{Symbol}) =
    schema(ts, columntable(data), hints)

# handle hints:
schema(ts::AbstractVector{<:AbstractTerm}, dt::ColumnTable,
       hints::Dict{Symbol}=Dict{Symbol,Any}()) =
    sch = Schema(t=>concrete_term(t, dt, hints) for t in ts)

schema(f::TermOrTerms, data, hints::Dict{Symbol}) =
    schema(filter(needs_schema, terms(f)), data, hints)

schema(f::TermOrTerms, data) = schema(f, data, Dict{Symbol,Any}())

"""
    concrete_term(t::Term, data[, hint])

Create concrete term from the placeholder `t` based on a data source and
optional hint.  If `data` is a table, the `getproperty` is used to extract the
appropriate column.

The `hint` can be a `Dict{Symbol}` of hints, or a specific hint, a concrete term
type (`ContinuousTerm` or `CategoricalTerm`), or an instance of some
`<:AbstractContrasts`, in which case a `CategoricalTerm` will be created using
those contrasts.

If no hint is provided (or `hint==nothing`), the `eltype` of the data is used:
`Number`s are assumed to be continuous, and all others are assumed to be
categorical.

# Example

```jldoctest
julia> concrete_term(term(:a), [1, 2, 3])
a(continuous)

julia> concrete_term(term(:a), [1, 2, 3], nothing)
a(continuous)

julia> concrete_term(term(:a), [1, 2, 3], CategoricalTerm)
a(DummyCoding:3→2)

julia> concrete_term(term(:a), [1, 2, 3], EffectsCoding())
a(EffectsCoding:3→2)

julia> concrete_term(term(:a), [1, 2, 3], Dict(:a=>EffectsCoding()))
a(EffectsCoding:3→2)

julia> concrete_term(term(:a), (a = [1, 2, 3], b = [0.0, 0.5, 1.0]))
a(continuous)
```
"""
concrete_term(t::Term, d, hints::Dict{Symbol}) = concrete_term(t, d, get(hints, t.sym, nothing))

function concrete_term(t::Term, dt::ColumnTable, hint)
    msg = checkcol(dt, t.sym)
    if msg != ""
        throw(ArgumentError(msg))
    end
    return concrete_term(t, getproperty(dt, t.sym), hint)
end

function concrete_term(t::Term, dt::ColumnTable, hints::Dict{Symbol})
    msg = checkcol(dt, t.sym)
    if msg != ""
        throw(ArgumentError(msg))
    end
    return concrete_term(t, getproperty(dt, t.sym), get(hints, t.sym, nothing))
end


concrete_term(t::Term, d) = concrete_term(t, d, nothing)

# if the "hint" is already an AbstractTerm, use that
# need this specified to avoid ambiguity
concrete_term(t::Term, d::ColumnTable, hint::AbstractTerm) = hint
concrete_term(t::Term, x, hint::AbstractTerm) = hint

# second possible fix for #97
concrete_term(t, d, hint) = t

concrete_term(t::Term, xs::AbstractVector{<:Number}, ::Nothing) = concrete_term(t, xs, ContinuousTerm)
function concrete_term(t::Term, xs::AbstractVector, ::Type{ContinuousTerm})
    μ, σ2 = StatsBase.mean_and_var(xs)
    min, max = extrema(xs)
    ContinuousTerm(t.sym, promote(μ, σ2, min, max)...)
end
# default contrasts: dummy coding
concrete_term(t::Term, xs::AbstractVector, ::Nothing) = concrete_term(t, xs, CategoricalTerm)
concrete_term(t::Term, xs::AbstractArray, ::Type{CategoricalTerm}) = concrete_term(t, xs, DummyCoding())

function concrete_term(t::Term, xs::AbstractArray, contrasts::AbstractContrasts)
    xlevels = levels(xs)
    xunique = unique(xs)
    xused = length(xlevels) == length(xunique) ? xlevels : intersect(xlevels, xunique)
    contrmat = ContrastsMatrix(contrasts, xused)
    CategoricalTerm(t.sym, contrmat)
end

"""
    apply_schema(t, schema::StatsModels.Schema[, Mod::Type = Nothing])

Return a new term that is the result of applying `schema` to term `t` with
destination model (type) `Mod`.  If `Mod` is omitted, `Nothing` will be used.

When `t` is a `ContinuousTerm` or `CategoricalTerm` already, the term will be returned
unchanged _unless_ a matching term is found in the schema.  This allows
selective re-setting of a schema to change the contrast coding or levels of a
categorical term, or to change a continuous term to categorical or vice versa.

When defining behavior for custom term types, it's best to dispatch on
[`StatsModels.Schema`](@ref) for the second argument.  Leaving it as `::Any` will work
in _most_ cases, but cause method ambiguity in some.
"""
apply_schema(t, schema) = apply_schema(t, schema, Nothing)
apply_schema(t, schema, Mod::Type) = t
apply_schema(terms::TupleTerm, schema, Mod::Type) = reduce(+, apply_schema.(terms, Ref(schema), Mod))

apply_schema(t::Term, schema::Schema, Mod::Type) = schema[t]
apply_schema(ft::FormulaTerm, schema::Schema, Mod::Type) =
    FormulaTerm(apply_schema(ft.lhs, schema, Mod),
                collect_matrix_terms(apply_schema(ft.rhs, schema, Mod)))
apply_schema(it::InteractionTerm, schema::Schema, Mod::Type) =
    InteractionTerm(apply_schema(it.terms, schema, Mod))

# for re-setting schema (in setcontrasts!)
apply_schema(t::Union{ContinuousTerm, CategoricalTerm}, schema::Schema, Mod::Type) =
    get(schema, term(t.sym), t)
apply_schema(t::MatrixTerm, sch::Schema, Mod::Type) =
    MatrixTerm(apply_schema.(t.terms, Ref(sch), Mod))

# TODO: special case this for <:RegressionModel ?
function apply_schema(t::ConstantTerm, schema::Schema, Mod::Type)
    t.n ∈ (-1, 0, 1) ||
        throw(ArgumentError("can't create InterceptTerm from $(t.n) " *
                            "(only -1, 0, and 1 allowed)"))
    InterceptTerm{t.n==1}()
end

# general idea is once we hit a FunctionTerm, we need to continue to
# apply_schema because there might be some child that is un-protected.  So we
# enter the Protected context and recursively apply_schema, and when we
# encounter `unprotect` we restore the old context and continue to recursively
# apply_schema
"""
    struct Protected{Ctx}

Represent a context in which `@formula` DSL syntax (e.g. `&` to construct
[`InteractionTerm`](@ref) rather than bitwise-and) and [`apply_schema`](@ref)
transformations should not apply.  This is automatically applied to the
arguments of a [`FunctionTerm`](@ref), meaning that by default calls to `+`,
`&`, or `~` inside a [`FunctionTerm`](@ref) will be interpreted as calls to the
normal Julia functions, rather than term union, interaction, or formula
separation.

The only special behavior with [`apply_schema`](@ref) inside a `Protected`
context is when a call to [`unprotect`](@ref) is encountered.  At that point,
everything below the call to `unprotect` is treated as formula-specific syntax.

A `Protected` context is created inside a [`FunctionTerm`](@ref) automatically,
but can be manually created with a call to [`protect`](@ref).
```
"""
struct Protected{Ctx} end
Base.broadcastable(x::Protected) = Ref(x)

"""
    protect(term::T)

Create a [`Protected`](@ref) context for interpreting `term` (and descendents) during
`apply_schema`.

Outside a [`@formula`](@ref), acts as a constructor for the singleton `Protected{T}`.

# Example

```jldoctest; setup = :(using Random; Random.seed!(1))
julia> d = (y=rand(4), a=[1:4;], b=rand(4));

julia> f = @formula(y ~ 1 + protect(a+b));

julia> modelmatrix(f.rhs, d)
4×2 Matrix{Float64}:
 1.0  1.91493
 1.0  2.19281
 1.0  3.77018
 1.0  4.78052

julia> d.a .+ d.b
4-element Vector{Float64}:
 1.9149290036628313
 2.1928081162458755
 3.7701803478856664
 4.7805192636751865
```
"""
protect(ctx) = Protected{ctx}()
# return instances rather than types to avoid method ambiguities using Type{<:Protected}

function apply_schema(t::FunctionTerm, schema::Schema, Mod::Type)
    args = apply_schema.(t.args, schema, protect(Mod))
    FunctionTerm(t.f, args, t.exorig)
end

apply_schema(t::FunctionTerm, schema::Schema, Ctx::Protected) =
    FunctionTerm(t.f, apply_schema.(t.args, schema, Ctx), t.exorig)
apply_schema(t, schema::Schema, Ctx::Protected) = t

function apply_schema(t::FunctionTerm{typeof(protect)}, schema::Schema, Ctx::Type)
    tt = only(t.args)
    apply_schema(tt, schema, protect(Ctx))
end

# protect in Protected context is a no-op
function apply_schema(t::FunctionTerm{typeof(protect)}, schema::Schema, Ctx::Protected)
    tt = only(t.args)
    apply_schema(tt, schema, Ctx)
end

"""
    unprotect(term)
    unprotect(::Protected{T})

Inside a [`@formula`], removes [`Protected`](@ref) status for the argument
term(s).  This allows the [`@formula`](@ref)-specific interpretation of
calls to `+`, `&`, `*`, and `~` to be restored inside an otherwise
[`Protected`](@ref) context.

When called outside a `@formula`, unwraps `Protected{T}` to `T`.

# Example

```jldoctest; setup = :(using Random; Random.seed!(1))
julia> d = (y=rand(4), a=[1.:4;], b=rand(4));

julia> f = @formula(y ~ 1 - unprotect(a&b));

julia> modelmatrix(f, d)
4×1 Matrix{Float64}:
  0.08507099633716864
  0.6143837675082491
 -1.310541043656999
 -2.1220770547007453

julia> 1 .- d.a .* d.b
4-element Vector{Float64}:
  0.08507099633716864
  0.6143837675082491
 -1.310541043656999
 -2.1220770547007453
```
"""
unprotect(::Protected{Ctx}) where {Ctx} = Ctx

function apply_schema(t::FunctionTerm{typeof(unprotect)}, schema::Schema, Ctx::Protected)
    tt = only(t.args)
    apply_schema(tt, schema, unprotect(Ctx))
end

"""
    has_schema(t::T) where {T<:AbstractTerm}

Return `true` if `t` has a schema, meaning that `apply_schema` would be a no-op.
"""
has_schema(t::AbstractTerm) = true
has_schema(t::ConstantTerm) = false
has_schema(t::Term) = false
has_schema(t::Union{ContinuousTerm,CategoricalTerm}) = true
has_schema(t::InteractionTerm) = all(has_schema(tt) for tt in t.terms)
has_schema(t::TupleTerm) = all(has_schema(tt) for tt in t)
has_schema(t::MatrixTerm) = has_schema(t.terms)
has_schema(t::FormulaTerm) = has_schema(t.lhs) && has_schema(t.rhs)
# FunctionTerms may always be transformed by apply_schema
has_schema(t::FunctionTerm) = false

struct FullRank
    schema::Schema
    already::Set{AbstractTerm}
end

FullRank(schema) = FullRank(schema, Set{AbstractTerm}())

Base.get(schema::FullRank, key, default) = get(schema.schema, key, default)
Base.merge(a::FullRank, b::FullRank) = FullRank(merge(a.schema, b.schema),
                                                union(a.already, b.already))

function apply_schema(t::FormulaTerm, schema::Schema, Mod::Type{<:StatisticalModel})
    schema = FullRank(schema)

    # Models with the drop_intercept trait do not support intercept terms,
    # usually because one is always necessarily included during fitting
    if drop_intercept(Mod)
        if hasintercept(t)
            throw(ArgumentError("Model type $Mod doesn't support intercept " *
                                "specified in formula $t"))
        end
        # start parsing as if we already had the intercept
        push!(schema.already, InterceptTerm{true}())
    elseif implicit_intercept(Mod) && !hasintercept(t) && !omitsintercept(t)
        t = FormulaTerm(t.lhs, InterceptTerm{true}() + t.rhs)
    end

    # only apply rank-promoting logic to RIGHT hand side
    FormulaTerm(apply_schema(t.lhs, schema.schema, Mod),
                collect_matrix_terms(apply_schema(t.rhs, schema, Mod)))
end

# strategy is: apply schema, then "repair" if necessary (promote to full rank
# contrasts).
#
# to know whether to repair, need to know context a term appears in.  main
# effects occur in "own" context.

"""
    apply_schema(t::AbstractTerm, schema::StatsModels.FullRank, Mod::Type)

Apply a schema, under the assumption that when a less-than-full rank model
matrix would be produced, categorical terms should be "promoted" to full rank
(where a categorical variable with ``k`` levels would produce ``k`` columns,
instead of ``k-1`` in the standard contrast coding schemes).  This step is
applied automatically when `Mod <: StatisticalModel`, but other types of models
can opt-in by adding a method like

```
StatsModels.apply_schema(t::FormulaTerm, schema::StatsModels.Schema, Mod::Type{<:MyModelType}) =
    apply_schema(t, StatsModels.FullRank(schema), mod)
```

See the section on [Modeling categorical data](@ref) in the docs for more
information on how promotion of categorical variables works.
"""
function apply_schema(t::ConstantTerm, schema::FullRank, Mod::Type)
    push!(schema.already, t)
    apply_schema(t, schema.schema, Mod)
end

apply_schema(t::InterceptTerm, schema::FullRank, Mod::Type) = (push!(schema.already, t); t)

# TODO: maybe change this to t::Any of ::AbstractTerm to catch
# categorical/continuous terms?
function apply_schema(t::AbstractTerm, schema::FullRank, Mod::Type)
    push!(schema.already, t)
    t = apply_schema(t, schema.schema, Mod) # continuous or categorical now
    apply_schema(t, schema, Mod, t) # repair if necessary
end

function apply_schema(t::InteractionTerm, schema::FullRank, Mod::Type)
    push!(schema.already, t)
    terms = apply_schema.(t.terms, Ref(schema.schema), Mod)
    terms = apply_schema.(terms, Ref(schema), Mod, Ref(t))
    InteractionTerm(terms)
end




# context doesn't matter for non-categorical terms
apply_schema(t, schema::FullRank, Mod::Type, context::AbstractTerm) = t
# when there's a context, check to see if any of the terms already seen would be
# aliased by this term _if_ it were full rank.
function apply_schema(t::CategoricalTerm, schema::FullRank, Mod::Type, context::AbstractTerm)
    aliased = drop_term(context, t)
    @debug "$t in context of $context: aliases $aliased\n  seen already: $(schema.already)"
    for seen in schema.already
        if symequal(aliased, seen)
            @debug "  aliased term already present: $seen"
            return t
        end
    end
    # aliased term not seen already:
    # add aliased term to already seen:
    push!(schema.already, aliased)
    # repair:
    new_contrasts = ContrastsMatrix(FullDummyCoding(), t.contrasts.levels)
    t = CategoricalTerm(t.sym, new_contrasts)
    @debug "  aliased term absent, repairing: $t"
    t
end

drop_term(from, to) = symequal(from, to) ? ConstantTerm(1) : from
drop_term(from::FormulaTerm, to) = FormulaTerm(from.lhs, drop_term(from.rhs, to))
drop_term(from::MatrixTerm, to) = MatrixTerm(drop_term(from.terms, to))
drop_term(from::TupleTerm, to) =
    tuple((t for t = from if !symequal(t, to))...)
function drop_term(from::InteractionTerm, t)
    terms = drop_term(from.terms, t)
    length(terms) > 1 ? InteractionTerm(terms) : terms[1]
end

"""
    termsyms(t::Terms.Term)

Extract the set of symbols referenced in this term.

This is needed in order to determine when a categorical term should have
standard (reduced rank) or full rank contrasts, based on the context it occurs
in and the other terms that have already been encountered.
"""
termsyms(t::AbstractTerm) = Set()
termsyms(t::InterceptTerm{true}) = Set(1)
termsyms(t::ConstantTerm) = Set((t.n,))
termsyms(t::Union{Term, CategoricalTerm, ContinuousTerm}) = Set([t.sym])
termsyms(t::InteractionTerm) = mapreduce(termsyms, union, t.terms)
termsyms(t::FunctionTerm) = Set([t.exorig])

symequal(t1::AbstractTerm, t2::AbstractTerm) = issetequal(termsyms(t1), termsyms(t2))


"""
    termvars(t::AbstractTerm)

The data variables that this term refers to.
"""
termvars(::AbstractTerm) = Symbol[]
termvars(t::Union{Term, CategoricalTerm, ContinuousTerm}) = [t.sym]
termvars(t::InteractionTerm) = mapreduce(termvars, union, t.terms)
termvars(t::TupleTerm) = mapreduce(termvars, union, t, init=Symbol[])
termvars(t::MatrixTerm) = termvars(t.terms)
termvars(t::FormulaTerm) = union(termvars(t.lhs), termvars(t.rhs))
termvars(t::FunctionTerm) = mapreduce(termvars, union, t.args, init=Symbol[])


"""
    StatsModels.@support_unprotect f sch_types...

Generate methods necessary for function `f` to support [`unprotect`](@ref)
inside of a `@formula` with a schema of types `sch_types`.  If not specified,
`sch_types` defaults to `(Schema, FullRank)` (the two schema types defined in
StatsModels itself).

Any function call that occurs as a child of a protected call is also protected
by default.  In order to support _unprotecting_ functions/operators that work
directly on `Term`s (like the built-in "special" operators `+`, `&`, `*`, and
`~`), we need to add methods for `apply_schema(::FunctionTerm{typeof(f)}, ...)`
that calls `f` on the captured arguments before further schema application.

This macro generates the necessary method for `f`.  For this to do something
reasonable, a few conditions must be met:

1. Methods must exist for `f(args::AbstractTerm...)` matching the specific
   signatures that users provide when calling `f` in `@formula` (and usually,
   returns an `AbstractTerm` of some kind).

2. The custom term type returned by `new_term = f(args::AbstractTerm...)` needs
   to do something reasonable when `modelcols` is called on it.

3. The thing returned by `modelcols(new_term, data)` needs to be something that
   can be consumed as input to whatever the parent call was for `f` in the
   original formula expression.

To take a concrete example, if we have a function `g` that can do something
meaningful with the output of `modelcols(::InteractionTerm, ...)`, then when a
user provides something like

    @formula(g(unprotect(a & b)))

that gets lowered to

    FunctionTerm(g, [FuntionTerm(&, [Term(:a), Term(:b)], ...)], ...)

and we need to convert it to something like

    FuntionTerm(g, [Term(:a) & Term(:b)], ...)

during schema application, which is what the method generated by
`@support_unprotect &` does.
"""
macro support_unprotect(op, sch_types...)
    sch_types = isempty(sch_types) ? (Schema, FullRank) : sch_types
    ex = quote end
    for sch_type in sch_types
        sub_ex = quote
            function StatsModels.apply_schema(t::StatsModels.FunctionTerm{typeof($op)},
                                              sch::$sch_type,
                                              Mod::Type)
                apply_schema(t.f(t.args...), sch, Mod)
            end
        end
        push!(ex.args, sub_ex)
    end
    return esc(ex)
end

for op in SPECIALS
    @eval @support_unprotect $op
end
