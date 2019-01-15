################################################################################
# Schemas for terms

# step 1: extract all Term symbols
# step 2: create empty Schema (Dict)
# step 3: for each term, create schema entry based on column from data store

# TODO: handle streaming (Data.RowTable) by iterating over rows and updating
# schemas in place

terms(t::FormulaTerm) = union(terms(t.lhs), terms(t.rhs))
terms(t::InteractionTerm) = terms(t.terms)
terms(t::FunctionTerm{Fo,Fa,names}) where {Fo,Fa,names} = Term.(names)
terms(t::AbstractTerm) = [t]
terms(t::MatrixTerm) = terms(t.terms)
terms(t::TupleTerm) = mapreduce(terms, union, t)

needs_schema(::AbstractTerm) = true
needs_schema(::ConstantTerm) = false
needs_schema(t) = false

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

# Example

```julia-repl
julia> d = (x=sample([:a, :b, :c], 10), y=rand(10));

julia> ts = [Term(:x), Term(:y)];

julia> schema(ts, d)
Dict{Any,Any} with 2 entries:
  x => x (3 levels): DummyCoding(2)
  y => y (continuous)

julia> schema(ts, d, Dict(:x => HelmertCoding()))
Dict{Any,Any} with 2 entries:
  x => x (3 levels): HelmertCoding(2)
  y => y (continuous)

julia> schema(ts, d, Dict(:y => CategoricalTerm))
Dict{Any,Any} with 2 entries:
  x => x (3 levels): DummyCoding(2)
  y => y (10 levels): DummyCoding(9)
```
"""
schema(data, hints=Dict{Symbol,Any}()) = schema(columntable(data), hints)
schema(dt::D, hints=Dict{Symbol,Any}()) where {D<:ColumnTable} =
    schema(Term.(collect(fieldnames(D))), dt, hints)
schema(ts::AbstractVector{<:AbstractTerm}, data, hints::Dict{Symbol}) =
    schema(ts, columntable(data), hints)

# handle hints:
function schema(ts::AbstractVector{<:AbstractTerm}, dt::ColumnTable,
                hints::Dict{Symbol}=Dict{Symbol,Any}())
    sch = Dict{Any,Any}()
    for t in ts
        if t.sym ∈ keys(hints)
            sch[t] = schema(t, dt, hints[t.sym])
        else
            sch[t] = schema(t, dt)
        end
    end
    return sch
end

schema(f::TermOrTerms, data, hints::Dict{Symbol}) =
    schema(filter(needs_schema, terms(f)), data, hints)

schema(f::TermOrTerms, data) = schema(f, data, Dict{Symbol,Any}())

"""
    schema(t::Term, data[, hint])

Create concrete term from the placeholder `t` based on a data source and
optional hint.  If `data` is a table, the `getproperty` is used to extract the
appropriate column.

The `hint` can be a concrete term type (`ContinuouTerm` or `CategoricalTerm`),
or an instance of some `<:AbstractContrasts`, in which case a `CategoricalTerm`
will be created using those contrasts.

If no hint is provided, the `eltype` of the data is used: `Number`s are assumed
to be continuous, and all others are assumed to be categorical.

# Example

```julia-repl
julia> schema(term(:a), [1, 2, 3])
a (continuous)

julia> schema(term(:a), [1, 2, 3], CategoricalTerm)
a (3 levels): DummyCoding(2)

julia> schema(term(:a), [1, 2, 3], EffectsCoding())
a (3 levels): EffectsCoding(2)

julia> schema(term(:a), (a = [1, 2, 3], b = rand(3)))
a (continuous)
```
"""
schema(t::Term, dt::ColumnTable) = schema(t, getproperty(dt, t.sym))
schema(t::Term, dt::ColumnTable, hint) = schema(t, getproperty(dt, t.sym), hint)

schema(t::Term, xs::AbstractVector{<:Number}) = schema(t, xs, ContinuousTerm)
function schema(t::Term, xs::AbstractVector, ::Type{ContinuousTerm})
    μ, σ2 = StatsBase.mean_and_var(xs)
    min, max = extrema(xs)
    ContinuousTerm(t.sym, promote(μ, σ2, min, max)...)
end
# default contrasts: dummy coding
schema(t::Term, xs::AbstractVector) = schema(t, xs, CategoricalTerm)
schema(t::Term, xs::AbstractArray, ::Type{CategoricalTerm}) = schema(t, xs, DummyCoding())

function schema(t::Term, xs::AbstractArray, contrasts::AbstractContrasts)
    contrmat = ContrastsMatrix(contrasts, sort!(unique(xs)))
    CategoricalTerm(t.sym, contrmat)
end

"""
    apply_schema(t, schema[, Mod::Type = Nothing])

Return a new term that is the result of applying `schema` to term `t` with
destination model (type) `Mod`.  If `Mod` is omitted, `Nothing` will be used.

When `t` is a `ContinuousTerm` or `CategoricalTerm` already, the term will be returned 
unchanged _unless_ a matching term is found in the schema.  This allows 
selective re-setting of a schema to change the contrast coding or levels of a 
categorical term, or to change a continuous term to categorical or vice versa.
"""
apply_schema(t, schema) = apply_schema(t, schema, Nothing)
apply_schema(t, schema, Mod) = t
apply_schema(terms::TupleTerm, schema, Mod) =
    apply_schema.(terms, Ref(schema), Mod)
apply_schema(t::Term, schema, Mod) = schema[t]
apply_schema(ft::FormulaTerm, schema, Mod) =
    FormulaTerm(apply_schema(ft.lhs, schema, Mod),
                extract_matrix_terms(apply_schema(ft.rhs, schema, Mod)))
apply_schema(it::InteractionTerm, schema, Mod) =
    InteractionTerm(apply_schema(it.terms, schema, Mod))

# for re-setting schema (in setcontrasts!)
apply_schema(t::Union{ContinuousTerm, CategoricalTerm}, schema, Mod) =
    get(schema, term(t.sym), t)
apply_schema(t::MatrixTerm, sch, Mod) = MatrixTerm(apply_schema.(t.terms, Ref(sch), Mod))


# TODO: special case this for <:RegressionModel ?
function apply_schema(t::ConstantTerm, schema, Mod)
    t.n ∈ (-1, 0, 1) ||
        throw(ArgumentError("can't create InterceptTerm from $(t.n) (only -1, 0, and 1 allowed)"))
    InterceptTerm{t.n==1}()
end

has_schema(t::AbstractTerm) = true
has_schema(t::Term) = false
has_schema(t::Union{ContinuousTerm,CategoricalTerm}) = true
has_schema(t::InteractionTerm) = all(has_schema(tt) for tt in t.terms)
has_schema(t::TupleTerm) = all(has_schema(tt) for tt in t)
has_schema(t::FormulaTerm) = has_schema(t.lhs) && has_schema(t.rhs)

mutable struct FullRank
    schema::Dict{Term,AbstractTerm}
    already::Set{AbstractTerm}
end

FullRank(schema) = FullRank(schema, Set{AbstractTerm}())

Base.get(schema::FullRank, key, default) = get(schema.schema, key, default)
Base.merge(a::FullRank, b::FullRank) = FullRank(merge(a.schema, b.schema),
                                                union(a.already, b.already))

function apply_schema(t::FormulaTerm, schema, Mod::Type{<:StatisticalModel})
    schema = FullRank(schema)

    # Models with the drop_intercept trait do not support intercept terms,
    # usually because they include one implicitly.
    if drop_intercept(Mod)
        if hasintercept(t)
            throw(ArgumentError("Model type $Mod doesn't support intercept " *
                                "specified in formula $t"))
        end
        # start parsing as if we've already have the intercept
        push!(schema.already, InterceptTerm{true}())
    elseif implicit_intercept(Mod) && !hasintercept(t) && !hasnointercept(t)
        t = FormulaTerm(t.lhs, InterceptTerm{true}() + t.rhs)
    end

    # only apply rank-promoting logic to RIGHT hand side
    FormulaTerm(apply_schema(t.lhs, schema.schema, Mod),
                extract_matrix_terms(apply_schema(t.rhs, schema, Mod)))
end

# strategy is: apply schema, then "repair" if necessary (promote to full rank
# contrasts).  
#
# to know whether to repair, need to know context a term appears in.  main
# effects occur in "own" context.

function apply_schema(t::ConstantTerm, schema::FullRank, Mod)
    push!(schema.already, t)
    apply_schema(t, schema.schema, Mod)
end

apply_schema(t::InterceptTerm, schema::FullRank, Mod) = (push!(schema.already, t); t)

function apply_schema(t::Term, schema::FullRank, Mod)
    push!(schema.already, t)
    t = apply_schema(t, schema.schema, Mod) # continuous or categorical now
    apply_schema(t, schema, Mod, t) # repair if necessary
end

function apply_schema(t::InteractionTerm, schema::FullRank, Mod)
    push!(schema.already, t)
    terms = apply_schema.(t.terms, Ref(schema.schema), Mod)
    terms = apply_schema.(terms, Ref(schema), Mod, Ref(t))
    InteractionTerm(terms)
end




# context doesn't matter for non-categorical terms
apply_schema(t, schema::FullRank, Mod, context::AbstractTerm) = t
# when there's a context, check to see if any of the terms already seen would be
# aliased by this term _if_ it were full rank.
function apply_schema(t::CategoricalTerm, schema::FullRank, Mod, context::AbstractTerm)
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
termsyms(t::InterceptTerm{true}) = Set([1])
termsyms(t::ConstantTerm) = Set([t.n])
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
termvars(t::FunctionTerm) = collect(t.names)
