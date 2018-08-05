abstract type AbstractTerm end
const TermOrTerms = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}

Base.show(io::IO, terms::NTuple{N, AbstractTerm}) where N = print(io, join(terms, " + "))
width(::T) where T<:AbstractTerm =
    throw(ArgumentError("terms of type $T have undefined width"))

# "lazy" or deferred term for data with unknown type etc.
struct Term <: AbstractTerm
    sym::Symbol
end
Base.show(io::IO, t::Term) = print(io, "$(t.sym)")
width(::Term) =
    throw(ArgumentError("Un-typed Terms have undefined width.  " *
                        "Did you forget to apply_schema?"))

struct FormulaTerm{L,R} <: AbstractTerm
    lhs::L
    rhs::R
end
Base.show(io::IO, t::FormulaTerm) = print(io, "$(t.lhs) ~ $(t.rhs)")

struct FunctionTerm{Forig,Fanon,Names} <: AbstractTerm
    forig::Forig
    fanon::Fanon
    names::NTuple{N,Symbol} where N
    exorig::Expr
end
FunctionTerm(forig::Fo, fanon::Fa, names::NTuple{N,Symbol}, exorig::Expr) where {Fo,Fa,N}  =
    FunctionTerm{Fo, Fa, names}(forig, fanon, names, exorig)
Base.show(io::IO, t::FunctionTerm) = print(io, ":($(t.exorig))")
width(::FunctionTerm) = 1

struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
Base.show(io::IO, it::InteractionTerm) = print(io, join(it.terms, "&"))

# TODO: ConstantTerm?
struct InterceptTerm{HasIntercept} <: AbstractTerm end
Base.show(io::IO, t::InterceptTerm{T}) where T = print(io, T ? "1" : "0")
width(::InterceptTerm{H}) where H = H ? 1 : 0

# Typed terms
struct ContinuousTerm <: AbstractTerm
    sym::Symbol
    series::Series
end
Base.show(io::IO, t::ContinuousTerm) = print(io, "$(t.sym) (continuous)")
width(::ContinuousTerm) = 1

struct CategoricalTerm{C,T,N} <: AbstractTerm
    sym::Symbol
    series::Series
    contrasts::ContrastsMatrix{C,T}
end
Base.show(io::IO, t::CategoricalTerm{C}) where C = print(io, "$(t.sym) (categorical: $C)")
width(::CategoricalTerm{C,T,N}) where {C,T,N} = N

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
# references to fields of namedtuple argument
#
# ACTUALLY: might make more sense to create a _multi-argument_ anonymous
# function, and let the FunctionTerm do teh conversion.  Then it's easier to
# handle both columns and a single row.  To do that, need to keep track of the
# symbols we've seen and make them the arguments of the anon function.
function nt_anon!(ex::Expr)
    check_call(ex)
    symbols = extract_symbols(ex)
    symbols_ex = Expr(:tuple, symbols...)
    f_anon_ex = Expr(:(->), symbols_ex, copy(ex))
    f_orig = ex.args[1]
    ex_orig = deepcopy(ex)
    ex.args = [:(StatsModels.FunctionTerm),
               esc(f_orig),
               f_anon_ex,
               tuple(symbols...),
               Meta.quot(ex_orig)]
    ex
end

extract_symbols(x) = Symbol[]
extract_symbols(x::Symbol) = [x]
extract_symbols(ex::Expr) =
    is_call(ex) ? mapreduce(extract_symbols, union, ex.args[2:end]) : Symbol[]

################################################################################
# operators on Terms that create new terms:


Base.:~(lhs::TermOrTerms, rhs::TermOrTerms) = FormulaTerm(lhs, rhs)

Base.:&(terms::AbstractTerm...) = InteractionTerm(terms)
Base.:&(it::InteractionTerm, terms::AbstractTerm...) = InteractionTerm((it.terms..., terms...))

Base.:+(terms::AbstractTerm...) = terms

################################################################################
# evaluating terms with data to generate model matrix entries

# TODO: @generated to unroll the getfield stuff
model_cols(ft::FunctionTerm{Fo,Fa,Names}, d::NamedTuple) where {Fo,Fa,Names} =
    ft.fanon.(getfield.(d, Names)...)

model_cols(t::ContinuousTerm, d::NamedTuple) = convert.(Float64, d[t.sym])

model_cols(t::CategoricalTerm, d::NamedTuple) = getindex(t.contrasts, d[t.sym], :)


# two options here: either special-case Data.Table (named tuple of vectors)
# vs. vanilla NamedTuple, or reshape and use normal broadcasting
model_cols(t::InteractionTerm, d::NamedTuple) =
    kron((model_cols(term, d) for term in t.terms)...)

function model_cols(t::InteractionTerm, d::Data.Table)
    # need to know the number of rows to pre-allocate
    rows = length(first(d))

    term_mats = [model_cols(term, d) for term in t.terms]
    output = Matrix{Float64}(undef, rows, prod(size.(term_mats, 2)))

    for i in 1:rows
        output[i, :] = kron((mat[i, :] for mat in term_mats)...)
    end

    output
end

model_cols(t::InterceptTerm{true}, d::NamedTuple) = ones(size(first(d)))

model_cols(ts::NTuple{N, AbstractTerm}, d::NamedTuple) where N =
    hcat([model_cols(t, d) for t in ts]...)
