abstract type AbstractTerm end
const TermOrTerms = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}

Base.show(io::IO, terms::NTuple{N, AbstractTerm}) where N = print(io, join(terms, " + "))
width(::T) where T<:AbstractTerm =
    throw(ArgumentError("terms of type $T have undefined width"))

"""
    struct Term <: AbstractTerm

A placeholder for a variable in a formula where the type (and necessary data
invariants) is not yet known.  This will be converted to a
[`ContinuousTerm`](@ref) or [`CategoricalTerm`](@ref) by [`apply_schema`](@ref).

# Fields

* `sym::Symbol`: The name of the data column this term refers to.
"""
struct Term <: AbstractTerm
    sym::Symbol
end
Base.show(io::IO, t::Term) = print(io, "$(t.sym)")
width(::Term) =
    throw(ArgumentError("Un-typed Terms have undefined width.  " *
                        "Did you forget to apply_schema?"))

"""
    struct ConstantTerm{T<:Number} <: AbstractTerm

Represents a literal number in a formula.  By default will be converted to
[`InterceptTerm`] by [`apply_schema`](@ref).

# Fields

* `n::T`: The number represented by this term.
"""
struct ConstantTerm{T<:Number} <: AbstractTerm
    n::T
end
Base.show(io::IO, t::ConstantTerm) = print(io, t.n)
width(::ConstantTerm) = 1

"""
    struct FormulaTerm{L,R} <: AbstractTerm

Represents an entire formula, with a left- and right-hand side.  These can be of
any type (captured by the type parameters).  

# Fields

* `lhs::L`: The left-hand side (e.g., response)
* `rhs::R`: The right-hand side (e.g., predictors)
"""
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
    args_parsed::Vector
end
FunctionTerm(forig::Fo, fanon::Fa, names::NTuple{N,Symbol}, exorig::Expr, args_parsed) where {Fo,Fa,N}  =
    FunctionTerm{Fo, Fa, names}(forig, fanon, names, exorig, args_parsed)
Base.show(io::IO, t::FunctionTerm) = print(io, ":($(t.exorig))")
width(::FunctionTerm) = 1

struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
Base.show(io::IO, it::InteractionTerm) = print(io, join(it.terms, "&"))
width(ts::InteractionTerm) = prod(width(t) for t in ts.terms)

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
Base.show(io::IO, t::CategoricalTerm{C,T,N}) where {C,T,N} =
    print(io, "$(t.sym) (categorical($N): $C)")
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

"""
    capture_call(call::Function, f_anon::Function, argnames::NTuple{N,Symbol}, ex_orig::Expr)

When the [`@formula`](@ref) macro encounters a call to a function that's not 
part of the DSL, it replaces the expression with a call to `capture_call` with 
arguments: 

* `call`: the original function that was called.
* `f_anon`: an anonymous function that calls the original expression, replacing 
  each symbol with one argument to the anonymous function
* `argnames`: the symbols from the original expression corresponding to each 
  argument of `f_anon`
* `ex_orig`: the original (quoted) expression before [`capture_call_ex!`](@ref).

The default behavior is to pass these arguments to the `FunctionTerm` constructor.
This default behavior can be overridden by dispatching on `call`.  That is, to 
change how calls to `myfun` in a formula are handled, add a method for 
    
    capture_call(::typeof(myfun), args...)

Alternatively, you can register `myfun` as a "special" function via

    StatsModels.is_special(Val(:myfun))

In this case, calls to `myfun` in a formula will be passed through, with symbol
arguments wrapped in `Term`s.
"""
capture_call(args...) = FunctionTerm(args...)

extract_symbols(x) = Symbol[]
extract_symbols(x::Symbol) = [x]
extract_symbols(ex::Expr) =
    is_call(ex) ? mapreduce(extract_symbols, union, ex.args[2:end]) : Symbol[]

################################################################################
# operators on Terms that create new terms:


Base.:~(lhs::TermOrTerms, rhs::TermOrTerms) = FormulaTerm(lhs, rhs)

Base.:&(terms::AbstractTerm...) = InteractionTerm(terms)
Base.:&(it::InteractionTerm, terms::AbstractTerm...) = InteractionTerm((it.terms..., terms...))

Base.:+(terms::AbstractTerm...) = (unique(terms)..., )

################################################################################
# evaluating terms with data to generate model matrix entries

catdims(::Data.Table) = 2
catdims(::NamedTuple) = 1

model_cols(ts::NTuple{N, AbstractTerm}, d::NamedTuple) where {N} =
    cat([model_cols(t, d) for t in ts]..., dims=catdims(d))


# TODO: @generated to unroll the getfield stuff
model_cols(ft::FunctionTerm{Fo,Fa,Names}, d::NamedTuple) where {Fo,Fa,Names} =
    ft.fanon.(getfield.(Ref(d), Names)...)

model_cols(t::ContinuousTerm, d::NamedTuple) = convert.(Float64, d[t.sym])

model_cols(t::CategoricalTerm, d::NamedTuple) = getindex(t.contrasts, d[t.sym], :)


# an "inside out" kronecker-like product based on broadcasting reshaped arrays
# for a single row, some will be scalars, others possibly vectors.  for a whole
# table, some will be vectors, possibly some matrices
function kron_insideout(op::Function, args...)
    args = [reshape(a, ones(Int, i-1)..., :) for (i,a) in enumerate(args)]
    vec(broadcast(op, args...))
end

function row_kron_insideout(op::Function, args...)
    args = [reshape(a, size(a,1), ones(Int, i-1)..., :) for (i,a) in enumerate(args)]
    reshape(broadcast(op, args...), size(args[1],1), :)
end

# two options here: either special-case Data.Table (named tuple of vectors)
# vs. vanilla NamedTuple, or reshape and use normal broadcasting
model_cols(t::InteractionTerm, d::NamedTuple) =
    kron_insideout(*, (model_cols(term, d) for term in t.terms)...)

function model_cols(t::InteractionTerm, d::Data.Table)
    row_kron_insideout(*, (model_cols(term, d) for term in t.terms)...)
end

model_cols(t::InterceptTerm{true}, d::NamedTuple) = ones(size(first(d)))
model_cols(t::InterceptTerm{false}, d) = Matrix{Float64}(undef, size(first(d),1), 0)

model_cols(t::FormulaTerm, d::NamedTuple) = (model_cols(t.lhs,d), model_cols(t.rhs, d))

vectorize(x::Tuple) = collect(x)
vectorize(x::AbstractVector) = x
vectorize(x) = [x]

termnames(::InterceptTerm{H}) where H = H ? "(Intercept)" : []
termnames(t::ContinuousTerm) = string(t.sym)
termnames(t::CategoricalTerm) = 
    ["$(t.sym): $name" for name in t.contrasts.termnames]
termnames(t::FunctionTerm) = string(t.exorig)
termnames(ts::NTuple{N,AbstractTerm}) where N = vcat(termnames.(ts)...)
termnames(t::InteractionTerm) =
    kron_insideout((args...) -> join(args, " & "), termnames.(t.terms)...)

################################################################################
# old Terms features:

hasintercept(t::AbstractTerm) = InterceptTerm{true}() ∈ terms(t) || ConstantTerm(1) ∈ terms(t)

hasresponse(t) = false
hasresponse(t::FormulaTerm{RHS, LHS}) where {RHS, LHS} = RHS !== nothing

# convenience converters
term(n::Number) = ConstantTerm(n)
term(s::Symbol) = Term(s)
term(args...) = term.(args)
term(t::AbstractTerm) = t
