abstract type AbstractTerm end

Base.show(io::IO, terms::NTuple{N, AbstractTerm}) where N = print(io, join(terms, " + "))

# "lazy" or deferred term for data with unknown type etc.
struct Term <: AbstractTerm
    sym::Symbol
end
Base.show(io::IO, t::Term) = print(io, "$(t.sym)")

struct FormulaTerm{L,R} <: AbstractTerm
    lhs::L
    rhs::R
end
Base.show(io::IO, t::FormulaTerm) = print(io, "$(t.lhs) ~ $(t.rhs)")

struct FunctionTerm{Forig,Fanon} <: AbstractTerm
    forig::Forig
    fanon::Fanon
    exorig::Expr
end
Base.show(io::IO, t::FunctionTerm) = print(io, ":($(t.exorig))")

struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
Base.show(io::IO, it::InteractionTerm) = print(io, join(it.terms, "&"))

# TODO: ConstantTerm?
struct InterceptTerm{HasIntercept} <: AbstractTerm end
Base.show(io::IO, t::InterceptTerm{T}) where T = print(io, T ? "1" : "0")

# Typed terms
struct ContinuousTerm <: AbstractTerm
    sym::Symbol
    series::Series
end
Base.show(io::IO, t::ContinuousTerm) = print(io, "$(t.sym) (continuous)")

struct CategoricalTerm{C,T,N} <: AbstractTerm
    sym::Symbol
    series::Series
    contrasts::ContrastsMatrix{C,T}
end
Base.show(io::IO, t::CategoricalTerm) = print(io, "$(t.sym) (categorical)")

# constructor that computes the width based on the contrasts matrix
CategoricalTerm(sym::Symbol, counts::Series, contrasts::ContrastsMatrix{C,T}) where {C,T} =
    CategoricalTerm{C,T,length(contrasts.termnames)}(sym, counts, contrasts)

# Model terms
struct ResponseTerm{Ts} <: AbstractTerm
    terms::Ts
end

struct PredictorsTerm{Ts} <: AbstractTerm
    terms::Ts
end


# create an anonymous function from an Expr, replacing the arguments with
function nt_anon!(ex::Expr)
    check_call(ex)
    replaced = Vector{Symbol}()
    tup_sym = gensym()
    nt_ex = Expr(:(->), tup_sym, replace_symbols!(copy(ex), replaced, tup_sym))
    f_orig = ex.args[1]
    ex_orig = deepcopy(ex)
    ex.args = [:(StatsModels.FunctionTerm), nt_ex, esc(f_orig), Meta.quot(ex_orig)]
    ex
end

replace_symbols!(x, replaced, tup::Symbol) = x

function replace_symbols!(x::Symbol, replaced, tup::Symbol)
    push!(replaced, x)
    Expr(:., tup, Meta.quot(x))
end

function replace_symbols!(ex::Expr, replaced, tup::Symbol)
    if is_call(ex)
        ex.args[2:end] .= [replace_symbols!(x, replaced, tup) for x in ex.args[2:end]]
    end
    ex
end

const TermOrTuple = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}

Base.:~(lhs::TermOrTuple, rhs::TermOrTuple) = FormulaTerm(lhs, rhs)

Base.:&(terms::AbstractTerm...) = InteractionTerm(terms)
Base.:&(it::InteractionTerm, terms::AbstractTerm...) = InteractionTerm((it.terms..., terms...))

Base.:+(terms::AbstractTerm...) = terms



################################################################################
# Schemas for terms

# step 1: extract all Term symbols
# step 2: create empty Schema (Dict)
# step 3: for each term, create schema entrybased on column from data store



terms(t::FormulaTerm) = union(terms(t.lhs), terms(t.rhs))
terms(t::InteractionTerm) = terms(t.terms)
terms(t::AbstractTerm) = Set{Any}([t])
terms(t::NTuple{N, AbstractTerm}) where N = mapreduce(terms, union, t)

needs_schema(t::Term) = true
needs_schema(t) = false

# handle hints:
function schema(f::FormulaTerm, dt::Data.Table, hints::Dict{Symbol,Any})
    ts = terms(f)
    sch = Dict{Any,Any}()
    for t in filter(needs_schema, ts)
        if t.sym ∈ keys(hints)
            sch[t] = schema(t, dt, hints[t.sym])
        else
            sch[t] = schema(t, dt)
        end
    end
    return sch
end

schema(f::FormulaTerm, dt::Data.Table) = schema(f, dt, Dict{Symbol,Any}())

schema(t::Term, dt::Data.Table) = schema(t, dt[t.sym])

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
