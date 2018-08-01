abstract type AbstractTerm end

# "lazy" or deferred term for data with unknown type etc.
struct Term <: AbstractTerm
    sym::Symbol
end

struct FormulaTerm{L,R} <: AbstractTerm
    lhs::L
    rhs::R
end

struct FunctionTerm{Forig,Fanon} <: AbstractTerm
    forig::Forig
    fanon::Fanon
    exorig::Expr
end

struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end

struct InterceptTerm <: AbstractTerm end

# Typed terms
struct ContinuousTerm <: AbstractTerm
    sym::Symbol
end

struct CategoricalTerm{N} <: AbstractTerm
    sym::Symbol
    contrasts::ContrastsMatrix
end

# Model terms
struct ResponseTerm{Ts} <: AbstractTerm
    terms::Ts
end

struct PredictorsTerm{Ts} <: AbstractTerm
    terms::Ts
end


# create an anonymous function from an Expr, replacing the arguments with
function nt_anon(ex::Expr)
    check_call(ex)
    replaced = Vector{Symbol}()
    tup_sym = gensym()
    nt_ex = Expr(:(->), tup_sym, replace_symbols!(copy(ex), replaced, tup_sym))
    f_orig = ex.args[1]
    Expr(:call, :(FunctionTerm), nt_ex, esc(f_orig), esc(Meta.quot(ex)))
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
