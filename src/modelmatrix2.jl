# Experiments in Formula->Term tree->ModelMatrix

# Two stage strategy.
# First, apply data schema with set_schema!:
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

function set_schema!(terms::Term{:+}, source::AbstractDataFrame)
    already = Set()
    map!(t -> set_schema!(t, already, source), terms.children)
    terms
end

const DEFAULT_CONTRASTS = DummyCoding

# TODO: could use "context" (rest of term) rather than aliases, to avoid
# calculating aliases for continuous terms.
function set_schema!(term::EvalTerm, aliases::Set, already::Set, source)
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

function set_schema!(term::Term{:&}, already::Set, source)
    push!(already, Set(term.children))
    term.children = map(c -> set_schema!(c,
                                     Set(d for d in term.children if d!=c),
                                     already,
                                     source),
                        term.children)
    return term
end

function set_schema!(term::EvalTerm, already::Set, source)
    push!(already, Set([term]))
    return set_schema!(term, Set([Term{1}()]), already, source)
end

# set_schema!(x::Any, already::Set, source) = (push!(already, Set([x])); x)

# what to do about set_schema! when schema's already been set? could just error,
# or better yet check whether schema matches.  for categorical terms, can
# instantiate the contrasts matrix again adn that will do the check?

function set_schema!(term::ContinuousTerm, aliases::Set, already::Set, source)
    if is_categorical(term.name, source)
        throw(ArgumentError("Term $(term) is continuous but $(term.name) is" *
                            " categorical in schema"))
    else
        return ContinuousTerm(term.name, source)
    end
end

function set_schema!(term::CategoricalTerm, aliases::Set, already::Set, source)
    if is_categorical(term.name, source)
        return CategoricalTerm(term.name,
                               ContrastsMatrix(term.contrasts,
                                               source[term.name]),
                               source)
    else
        throw(ArgumentError("Term $(term) is categorical but $(term.name) is" *
                            " continuous in schema"))
    end
end

set_schema!(term::Union{ContinuousTerm, CategoricalTerm}, already::Set, source) =
    set_schema!(term, Set([Term{1}()]), already, source)

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

nc(t::Term{:+}) = mapreduce(nc, +, t.children)
nc(t::Term{:&}) = mapreduce(nc, *, t.children)
nc(::ContinuousTerm) = 1
nc(t::CategoricalTerm) = size(t.contrasts.matrix, 2)
nc(t::EvalTerm) = throw(ArgumentError("Can't compute number of columns for " *
                                      "un-evaluated term $t. Use set_schema!"))
nc(::Term{1}) = 1
nc(::AbstractTerm) = 0

modelmat_cols!(dest::AbstractArray, ::Term{1}) = fill!(dest, 1)
function modelmat_cols!(dest::AbstractArray, ::AbstractTerm) end
modelmat_cols!(dest::AbstractArray, t::ContinuousTerm) = copy!(dest, t.source[t.name])
function modelmat_cols!(dest::AbstractArray, t::CategoricalTerm)
    v = t.source[t.name]
    reindex = [findfirst(t.contrasts.levels, l) for l in levels(v)]
    copy!(dest, t.contrasts.matrix[reindex[v.refs], :])
end

function model_matrix(terms::AbstractTerm, data::AbstractDataFrame)
    
    terms = set_schema!(Term{:+}(terms), data)

    term_sizes = map(nc, terms.children)
    mat_size = (size(data, 1), sum(term_sizes))

    mat = Matrix(mat_size...)

    first_col = 0
    for t in terms.children
        ncol = nc(t)
        col_inds = first_col + (1:ncol)
        first_col += ncol
        modelmat_cols!(view(mat, :, col_inds), t)
    end

    return mat
end


# to generate model matrix:
#   calculate size of model matrix (sum of column sizes)
#   for each term, fill in columns
#
# to fill in columns:
#   if intercept, fill!(1.)
#   if continuous, copy!(dest, source[t.name])
#   if categorical, reindex and copy! OR: iterate over columns, and copy.
#   if interaction:
#     generate strides (cumprod sizes)
#     for each column idx:
#       generate indices of component terms (using ind2sub)
#       write first column in place, then for rest iterate and multiply in place
#       (TODO: can do this MUCH more efficiently by fusing contrast matrices,
#        but tricky to handle both continuous and categorical)

################################################################################

import StatsModels: term

d = DataFrame(a = 1:10, b = categorical(repeat(["a", "b"], outer=5)))

contrasts(t::Term) = map(contrasts, t.children)
contrasts(t::Term{1}) = nothing
contrasts(t::ContinuousTerm) = nothing
contrasts{C}(t::CategoricalTerm{C}) = C

t1 = set_schema!(term(:(a+b)), d)
t2 = set_schema!(term(:(1+a+b)), d)

t3 = set_schema!(term(:(a+b+a&b)), d)
t4 = set_schema!(term(:(1+a+b+a&b)), d)

