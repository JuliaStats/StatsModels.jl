abstract type AbstractTerm end
const TupleTerm = NTuple{N, AbstractTerm} where N
const TermOrTerms = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}

Base.show(io::IO, terms::TupleTerm) = print(io, join(terms, " + "))
width(::T) where {T<:AbstractTerm} =
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
Base.show(io::IO, t::Term) = print(io, t.sym)
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
FunctionTerm(forig::Fo, fanon::Fa, names::NTuple{N,Symbol},
             exorig::Expr, args_parsed) where {Fo,Fa,N}  =
    FunctionTerm{Fo, Fa, names}(forig, fanon, names, exorig, args_parsed)
Base.show(io::IO, t::FunctionTerm) = print(io, ":($(t.exorig))")
width(::FunctionTerm) = 1

struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
Base.show(io::IO, it::InteractionTerm) = print(io, join(it.terms, "&"))
width(ts::InteractionTerm) = prod(width(t) for t in ts.terms)

struct InterceptTerm{HasIntercept} <: AbstractTerm end
Base.show(io::IO, t::InterceptTerm{H}) where {H} = print(io, H ? "1" : "0")
width(::InterceptTerm{H}) where {H} = H ? 1 : 0

# Typed terms
struct ContinuousTerm{T} <: AbstractTerm
    sym::Symbol
    mean::T
    var::T
    min::T
    max::T
end
Base.show(io::IO, t::ContinuousTerm) = print(io, "$(t.sym) (continuous)")
width(::ContinuousTerm) = 1

struct CategoricalTerm{C,T,N} <: AbstractTerm
    sym::Symbol
    contrasts::ContrastsMatrix{C,T}
end
Base.show(io::IO, t::CategoricalTerm{C,T,N}) where {C,T,N} =
    print(io, "$(t.sym) ($(length(t.contrasts.levels)) levels): $C($N)")
width(::CategoricalTerm{C,T,N}) where {C,T,N} = N

# constructor that computes the width based on the contrasts matrix
CategoricalTerm(sym::Symbol, contrasts::ContrastsMatrix{C,T}) where {C,T} =
    CategoricalTerm{C,T,length(contrasts.termnames)}(sym, contrasts)

"""
    MatrixTerm{Ts} <: AbstractTerm

A collection of terms that should be combined to produce a single matrix.
"""
struct MatrixTerm{Ts<:TupleTerm} <: AbstractTerm
    terms::Ts
end
# wrap single terms in a tuple
MatrixTerm(t::AbstractTerm) = MatrixTerm((t, ))

Base.show(io::IO, t::MatrixTerm) = show(io, t.terms)
width(t::MatrixTerm) = sum(width(tt) for tt in t.terms)

"""
    extract_matrix_terms(ts::TupleTerm)

Depending on whether the component terms are matrix terms (meaning they have
`is_matrix_term(T) == true`), `extract_matrix_terms` will return

1.  A single `MatrixTerm` (if all components are matrix terms)
2.  A tuple of the components (if none of them are matrix terms)
3.  A tuple of terms, with all matrix terms collected into a single `MatrixTerm`
    in the first element of the tuple, and the remaining non-matrix terms passed
    through unchanged.

By default all terms are matrix terms (that is,
`is_matrix_term(::Type{<:AbstractTerm}) = true`), the first case is by far the
most common.  The others are provided only for convenience when dealing with
specialized terms that can't be concatenated into a single model matrix, like
random effects terms in
[MixedModels.jl](https://github.com/dmbates/MixedModels.jl).

"""
function extract_matrix_terms(ts::TupleTerm)
    ismat = collect(is_matrix_term.(ts))
    if all(ismat)
        MatrixTerm(ts)
    elseif any(ismat)
        matterms = ts[ismat]
        (MatrixTerm(ts[ismat]), ts[.!ismat]...)
    else
        ts
    end
end
extract_matrix_terms(t::T) where {T<:AbstractTerm} =
    is_matrix_term(T) ? MatrixTerm((t, )) : t
extract_matrix_terms(t::MatrixTerm) = t


"""
    is_matrix_term(::Type{<:AbstractTerm})

Does this type of term get concatenated with other matrix terms into a single
model matrix?  This controls the behavior of the `MatrixTerm` constructor.  If
all the component terms passed to `MatrixTerm` have `is_matrix_term(T) = true`,
then a single `MatrixTerm` is constructed.  If any of the terms have
`is_matrix_term(T) = false` then the constructor returns a tuple of terms; one
`MatrixTerm` (if there are any matrix terms), and one for each of the other
non-matrix terms.

Since all "normal" terms which describe one or more model matrix columns are
matrix terms, this defaults to `true` for any `AbstractTerm`.

An example of a non-matrix term is a random effect term in
[MixedModels.jl](https://github.com/dmbates/MixedModels.jl).
"""
is_matrix_term(::T) where {T} = is_matrix_term(T)
is_matrix_term(::Type{<:AbstractTerm}) = true


"""
    capture_call(f_orig::Function, f_anon::Function, argnames::NTuple{N,Symbol}, 
                 ex_orig::Expr, args_parsed::Vector{AbstractTerm})

When the [`@formula`](@ref) macro encounters a call to a function that's not 
part of the DSL, it replaces the expression with a call to `capture_call` with 
arguments: 

* `f_orig`: the original function that was called.
* `f_anon`: an anonymous function that calls the original expression, replacing 
  each symbol with one argument to the anonymous function
* `names`: the symbols from the original expression corresponding to each 
  argument of `f_anon`
* `ex_orig`: the original (quoted) expression before [`capture_call_ex!`](@ref).
* `args_parsed`: a vector of the original arguments, wrapped in terms with the 
  special formula DSL rules applied, as if `f_orig` was a special DSL call.

The default behavior is to pass these arguments to the `FunctionTerm` constructor.
This default behavior can be overridden by dispatching on `call`.  That is, to 
change how calls to `myfun` in a formula are handled in the context of `MyModel`, 
add a method:
    
    apply_schema(t::FunctionTerm{typeof(myfun)}, schema, ::Type{MyModel})

If you simply want to pass the arguments to the original call, parsed as if the 
call was a special, then you can use

    apply_schema(t::FunctionTerm{typeof(myfun)}, schema, ::Type{MyModel}) =
        apply_schema(myfun(t.args_parsed...), schema, MyModel)

For this to work, `myfun(args::AbstractTerm...)` should return another 
`AbstractTerm`, which has an `apply_schema` method already defined for it.
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
Base.:&(term::AbstractTerm) = term
Base.:&(it::InteractionTerm, terms::AbstractTerm...) = InteractionTerm((it.terms..., terms...))

Base.:+(terms::AbstractTerm...) = (unique(terms)..., )
Base.:+(as::TupleTerm, b::AbstractTerm) = (as..., b)
Base.:+(a::AbstractTerm, bs::TupleTerm) = (a, bs...)

################################################################################
# evaluating terms with data to generate model matrix entries

function model_cols(t, d::D) where D
    Tables.istable(d) || throw(ArgumentError("Data of type $D is not a table!"))
    model_cols(t, columntable(d))
end

model_cols(ts::TupleTerm, d::NamedTuple) = model_cols.(ts, Ref(d))

# TODO: @generated to unroll the getfield stuff
model_cols(ft::FunctionTerm{Fo,Fa,Names}, d::NamedTuple) where {Fo,Fa,Names} =
    ft.fanon.(getfield.(Ref(d), Names)...)

model_cols(t::ContinuousTerm, d::NamedTuple) = Float64.(d[t.sym])

model_cols(t::CategoricalTerm, d::NamedTuple) = t.contrasts[d[t.sym], :]


# an "inside out" kronecker-like product based on broadcasting reshaped arrays
# for a single row, some will be scalars, others possibly vectors.  for a whole
# table, some will be vectors, possibly some matrices
function kron_insideout(op::Function, args...)
    args = (reshape(a, ones(Int, i-1)..., :) for (i,a) in enumerate(args))
    vec(broadcast(op, args...))
end

function row_kron_insideout(op::Function, args...)
    rows = size(args[1], 1)
    args = (reshape(a, size(a,1), ones(Int, i-1)..., :) for (i,a) in enumerate(args))
    reshape(broadcast(op, args...), rows, :)
end

# two options here: either special-case ColumnTable (named tuple of vectors)
# vs. vanilla NamedTuple, or reshape and use normal broadcasting
model_cols(t::InteractionTerm, d::NamedTuple) =
    kron_insideout(*, (model_cols(term, d) for term in t.terms)...)

function model_cols(t::InteractionTerm, d::ColumnTable)
    row_kron_insideout(*, (model_cols(term, d) for term in t.terms)...)
end

model_cols(t::InterceptTerm{true}, d::NamedTuple) = ones(size(first(d)))
model_cols(t::InterceptTerm{false}, d) = Matrix{Float64}(undef, size(first(d),1), 0)

model_cols(t::FormulaTerm, d::NamedTuple) = (model_cols(t.lhs,d), model_cols(t.rhs, d))

function model_cols(t::MatrixTerm, d::ColumnTable)
    mat = reduce(hcat, (model_cols(tt, d) for tt in t.terms))
    reshape(mat, size(mat, 1), :)
end

model_cols(t::MatrixTerm, d::NamedTuple) =
    reduce(vcat, (model_cols(tt, d) for tt in t.terms))

vectorize(x::Tuple) = collect(x)
vectorize(x::AbstractVector) = x
vectorize(x) = [x]

termnames(::InterceptTerm{H}) where {H} = H ? "(Intercept)" : []
termnames(t::ContinuousTerm) = string(t.sym)
termnames(t::CategoricalTerm) = 
    ["$(t.sym): $name" for name in t.contrasts.termnames]
termnames(t::FunctionTerm) = string(t.exorig)
termnames(ts::TupleTerm) = reduce(vcat, termnames.(ts))
termnames(t::MatrixTerm) = termnames(t.terms)
termnames(t::InteractionTerm) =
    kron_insideout((args...) -> join(args, " & "), vectorize.(termnames.(t.terms))...)

################################################################################
# old Terms features:

hasintercept(t::AbstractTerm) = InterceptTerm{true}() ∈ terms(t) || ConstantTerm(1) ∈ terms(t)
hasnointercept(t::AbstractTerm) =
    InterceptTerm{false}() ∈ terms(t) ||
    ConstantTerm(0) ∈ terms(t) ||
    ConstantTerm(-1) ∈ terms(t)

hasresponse(t) = false
hasresponse(t::FormulaTerm{LHS}) where {LHS} = LHS !== nothing

# convenience converters
term(n::Number) = ConstantTerm(n)
term(s::Symbol) = Term(s)
term(args...) = term.(args)
term(t::AbstractTerm) = t
