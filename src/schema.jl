################################################################################
# Schemas for terms

# step 1: extract all Term symbols
# step 2: create empty Schema (Dict)
# step 3: for each term, create schema entrybased on column from data store

# TODO: handle streaming (Data.RowTable) by iterating over rows and updating
# schemas in place

terms(t::FormulaTerm) = union(terms(t.lhs), terms(t.rhs))
terms(t::InteractionTerm) = terms(t.terms)
terms(t::AbstractTerm) = Set{Any}([t])
terms(t::NTuple{N, AbstractTerm}) where N = mapreduce(terms, union, t)

needs_schema(t::AbstractTerm) = true
needs_schema(::InterceptTerm) = false
needs_schema(::FunctionTerm) = false
needs_schema(t) = false

schema(dt::D, hints=Dict{Symbol,Any}()) where {D<:Data.Table} =
    schema(Term.(fieldnames(D)), dt, hints)

# handle hints:
function schema(ts::NTuple{N,AbstractTerm}, dt::Data.Table, hints::Dict{Symbol}) where N
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

schema(f::FormulaTerm, dt::Data.Table, hints::Dict{Symbol}) =
    schema(filter(needs_schema, terms(f)), dt, hints)

schema(f::FormulaTerm, dt::Data.Table) = schema(f, dt, Dict{Symbol,Any}())

schema(t::Term, dt::Data.Table) = schema(t, dt[t.sym])
schema(t::Term, dt::Data.Table, hint) = schema(t, dt[t.sym], hint)

schema(t::Term, xs::AbstractVector) = schema(t::Term, xs, ContinuousTerm)
schema(t::Term, xs::AbstractVector, ::Type{ContinuousTerm}) =
    ContinuousTerm(t.sym, fit!(Series(Variance()), xs))

# default contrasts: dummy coding
schema(t::Term, xs::CategoricalArray) = schema(t, xs, DummyCoding())
schema(t::Term, xs::AbstractArray, ::Type{CategoricalTerm}) = schema(t, xs, DummyCoding())

function schema(t::Term, xs::AbstractArray, contrasts::AbstractContrasts)
    counts = fit!(Series(CountMap(eltype(xs))), xs)
    contrmat = ContrastsMatrix(contrasts, collect(keys(counts.stats[1])))
    CategoricalTerm(t.sym, counts, contrmat)
end

# TODO: add methods for schema(::Continuous/CategoricalTerm) (to re-set/validate schema)



# now to _set_ the schema in formula...most straightforward way is to just look
# up each term in the schema and replace it (calculating width of interaction
# terms and things like that) but we want to handle the rank correcting stuff
# too.  maybe that's best thought of as a kind of re-write rule?  or as a
# special kind of schema/wrapper type?  then if it's just a dict, the "vanilla"
# version is available...
#
# so what does that wrapper look like?  holds onto the terms that have been seen
# so far, checks against that...

apply_schema(ft::FormulaTerm, data::Data.Table, args...) =
    apply_schema(ft, schema(ft, data, args...))

apply_schema(t, schema) = t
apply_schema(terms::NTuple{N,AbstractTerm}, schema) where N = apply_schema.(terms, Ref(schema))
apply_schema(t::Term, schema) = schema[t]
apply_schema(ft::FormulaTerm, schema) = FormulaTerm(apply_schema(ft.lhs, schema),
                                                    apply_schema(ft.rhs, schema))
apply_schema(it::InteractionTerm, schema) = InteractionTerm(apply_schema(it.terms, schema))


mutable struct FullRank
    schema
    already::Set
end

FullRank(schema) = FullRank(schema, Set())

apply_schema(t, schema, ::Type{FullRank}) = apply_schema(t, FullRank(schema))

# only apply rank-promoting logic to RIGHT hand side
apply_schema(t::FormulaTerm, schema::FullRank) =
    FormulaTerm(apply_schema(t.lhs, schema.schema),
                apply_schema(t.rhs, schema))

# strategy is: apply schema, then "repair" if necessary (promote to full rank
# contrasts).  
#
# to know whether to repair, need to know context a term appears in.  main
# effects occur in "own" context.

apply_schema(t::InterceptTerm, schema::FullRank) = (push!(schema.already, t); t)

function apply_schema(t::Term, schema::FullRank)
    push!(schema.already, t)
    t = apply_schema(t, schema.schema) # continuous or categorical now
    apply_schema(t, schema, t) # repair if necessary
end

function apply_schema(t::InteractionTerm, schema::FullRank)
    push!(schema.already, t)
    terms = apply_schema.(t.terms, Ref(schema.schema))
    terms = apply_schema.(terms, schema, t)
    InteractionTerm(terms)
end




# context doesn't matter for non-categorical terms
apply_schema(t, schema::FullRank, context) = t
# when there's a context, check to see if any of the terms already seen would be
# aliased by this term _if_ it were full rank.
function apply_schema(t::CategoricalTerm, schema::FullRank, context)
    aliased = drop_term(context, t)
    @debug "$t in context of $context: aliases $aliased"
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
    t = CategoricalTerm(t.sym, t.series, new_contrasts)
    @debug "  aliased term absent, repairing: $t"
    t
end

drop_term(from, to) = symequal(from, to) ? InterceptTerm{true}() : from
function drop_term(from::InteractionTerm, t)
    terms = tuple((tt for tt = from.terms if !symequal(tt, t))...)
    length(terms) > 1 ? InteractionTerm(terms) : terms[1]
end

"""
    termsyms(t::Terms.Term)

Extract the Set of symbols referenced in this term.

This is needed in order to determine when a categorical term should have
standard (reduced rank) or full rank contrasts, based on the context it occurs
in and the other terms that have already been encountered.
"""
termsyms(t::AbstractTerm) = Set()
termsyms(t::InterceptTerm{true}) = Set([1])
termsyms(t::Union{Term, CategoricalTerm, ContinuousTerm}) = Set([t.sym])
termsyms(t::InteractionTerm) = mapreduce(termsyms, union, t.terms)
termsyms(t::FunctionTerm) = Set([t.exorig])

symequal(t1::AbstractTerm, t2::AbstractTerm) = issetequal(termsyms(t1), termsyms(t2))
