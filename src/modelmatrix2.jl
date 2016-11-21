# Experiments in Formula->Term tree->ModelMatrix

# Two stage strategy.
# First, add data to Term:
# * convert eval terms into ContinuousTerms and CategoricalTerms:
# * check redundancy and create contrasts
#
# Second, fill the model matrix (row):
# * get number of cols for each Term
# * pre-allocate a big enough vector/matrix
# * fill in each term's columns in place


using StatsModels, DataFrames
import StatsModels: AbstractTerm, Term, EvalTerm, ContrastsMatrix, FullDummyCoding

# TODO: seems like we'd actually want to NOT store source on each term, for
# example when it's an iterator of NamedTuples.  Actually, what is happening
# here is really more like mating with a _schema_ than with data itself.
type ContinuousTerm <: AbstractTerm
    name::Symbol
    source
end

type CategoricalTerm{C,T} <: AbstractTerm
    name::Symbol
    contrasts::ContrastsMatrix{C,T}
    source
end

Base.show(io::IO, t::ContinuousTerm) = print(io, "$(t.name)(continuous)")
Base.show{C}(io::IO, t::CategoricalTerm{C}) = print(io, "$(t.name)($C)")

Base.string(t::ContinuousTerm) = "$(t.name)(continuous)"
Base.string{C}(t::CategoricalTerm{C}) = "$(t.name)($C)"


is_categorical(::Union{CategoricalArray, NullableCategoricalArray}) = true
is_categorical(::Any) = false

is_categorical(name::Symbol, source::AbstractDataFrame) = is_categorical(source[name])

function datify!(terms::Term{:+}, source::AbstractDataFrame)
    already = Set()
    map!(t -> datify!(t, already, source), terms.children)
    terms
end

const DEFAULT_CONTRASTS = DummyCoding

# TODO: could use "context" (rest of term) rather than aliases, to avoid
# calculating aliases for continuous terms.
function datify!(term::EvalTerm, aliases::Set, already::Set, source)
    println("Processing term: $term\n  aliases: $aliases\n  already: $already")
    if is_categorical(term.name, source)
        if aliases in already
            contr = DEFAULT_CONTRASTS()
        else
            contr = FullDummyCoding()
            push!(already, aliases)
        end
        CategoricalTerm(term.name,
                        ContrastsMatrix(contr, levels(source[term.name])),
                        source)
    else
        ContinuousTerm(term.name, source)
    end
end

function datify!(term::Term{:&}, already::Set, source)
    push!(already, Set(term.children))
    map!(c -> datify!(c, Set(d for d in term.children if d!=c), already, source),
         term.children)
    return term
end

function datify!(term::EvalTerm, already::Set, source)
    push!(already, Set([term]))
    return datify!(term, Set([Term{1}()]), already, source)
end

datify!(x::Any, already::Set, source) = (push!(already, Set([x])); x)


# to add data to a term:
#   if +: initialize set of encountered terms. add data to each child.
#   if it's a main effect (EvalTerm), aliases 1. check for 1 and if found, use
#     normal contrasts. otherwise full rank and add 1 to set. then add the term
#     itself.
#   if interaction: for each child EvalTerm, aliases remaining. check if those
#     are present already. if so, use normal contrasts, otherwise full rank and
#     add alised terms to set. after all children checked, add set(children) to
#     set.
#   for others: ??? nothing.






################################################################################

import StatsModels: term

d = DataFrame(a = 1:10, b = categorical(repeat(["a", "b"], outer=5)))

datify!(term(:(a+b)), d)
datify!(term(:(1+a+b)), d)
