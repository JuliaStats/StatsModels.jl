abstract type AbstractTerm end
const TupleTerm = NTuple{N, AbstractTerm} where N
const TermOrTerms = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}

Base.show(io::IO, terms::TupleTerm) = print(io, join(terms, " + "))
width(::T) where {T<:AbstractTerm} =
    throw(ArgumentError("terms of type $T have undefined width"))

"""
    Term <: AbstractTerm

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
    ConstantTerm{T<:Number} <: AbstractTerm

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

"""
    FunctionTerm{Forig,Fanon,Names} <: AbstractTerm

Represents a call to a non-DSL function.  The first type parameter is the type
of the function as originally specified (e.g., `typeof(log)`), while the second
is the type of the anonymous function that will be applied elementwise to the
data table.

The `FunctionTerm` _also_ captures the arguments of the original call and parses
them _as if_ they were part of a special DSL call, applying the rules to expand
`*`, distribute `&` over `+`, and wrap symbols in `Term`s.  

By storing the function original called as a type parameter _and_
pessimistically parsing the arguments as if they're part of a special DSL call,
this allows custom syntax to be supported with minimal extra effort.  Packages
can simply dispatch on `apply_schema(f::FunctionTerm{typeof(special_syntax)},
schema, ::Type{MyModel})` and pull out the

# Fields

* `forig::Forig`: the original function (e.g., `log`)
* `fanon::Fanon`: the generated anonymous function (e.g., `(a, b) -> log(1+a+b)`)
* `names::Tuple{Vararg{Symbol}}`: the names of the arguments to the generated 
  anonymous function (e.g., (:a,:b))
* `exorig::Expr`: the original expression passed to `@formula`
* `args_parsed::Vector`: the arguments of the call passed to `@formula`, each 
  parsed _as if_ the call was a "special" DSL call.

# Example

```julia
julia> f = @formula(y ~ log(1 + a + b))
y ~ :(log(1 + a + b))

julia> typeof(f.rhs)
FunctionTerm{typeof(log),getfield(Main, Symbol("##9#10")),(:a, :b)}

julia> f.rhs.forig(1 + 3 + 4)
2.0794415416798357

julia> f.rhs.fanon(3, 4)
2.0794415416798357

julia> model_cols(f.rhs, (a=3, b=4))
2.0794415416798357

julia> model_cols(f.rhs, (a=[3, 4], b=[4, 5]))
2-element Array{Float64,1}:
 2.0794415416798357
 2.302585092994046 
```
"""
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

"""
    InteractionTerm{Ts} <: AbstractTerm

Represents an _interaction_ between two or more individual terms.  

Generated by combining multiple `AbstractTerm`s with `&` (which is what calls to
`&` in a `@formula` lower to)

# Fields

* `terms::Ts`: the terms that participate in the interaction.

# Example

```julia

```
"""
struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
Base.show(io::IO, it::InteractionTerm) = print(io, join(it.terms, "&"))
width(ts::InteractionTerm) = prod(width(t) for t in ts.terms)

"""
    InterceptTerm{HasIntercept} <: AbstractTerm

Represents the presence or (explicit) absence of an "intercept" term in a
regression model.  These terms are generated from [`ConstantTerm`](@ref)s in a
formula by `apply_schema(::ConstantTerm, schema, ::Type{<:StatisticalModel})`.
A `1` yields `InterceptTerm{true}`, and `0` or `-1` yield `InterceptTerm{false}`
(which explicitly omits an intercept for models which implicitly includes one
via the [`implicit_intercept`](@ref) trait).
"""
struct InterceptTerm{HasIntercept} <: AbstractTerm end
Base.show(io::IO, t::InterceptTerm{H}) where {H} = print(io, H ? "1" : "0")
width(::InterceptTerm{H}) where {H} = H ? 1 : 0

# Typed terms

"""
Represents a continuous variable, with a name and summary statistics.

# Fields

* `sym::Symbol`: The name of the variable
* `mean::T`: Mean
* `var::T`: Variance
* `min::T`: Minimum value
* `max::T`: Maximum value
"""
struct ContinuousTerm{T} <: AbstractTerm
    sym::Symbol
    mean::T
    var::T
    min::T
    max::T
end
Base.show(io::IO, t::ContinuousTerm) = print(io, "$(t.sym) (continuous)")
width(::ContinuousTerm) = 1

"""
Represents a categorical term, with a name and [`ContrastsMatrix`](@ref)

# Fields

* `sym::Symbol`: The name of the variable
* `contrasts::ContrastsMatrix`: A contrasts matrix that captures the unique 
  values this variable takes on and how they are mapped onto numerical 
  predictors.
"""
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

A collection of terms that should be combined to produce a single numeric matrix.

A matrix term is created by [`apply_schema`](@ref) from a tuple of terms using 
[`extract_matrix_terms`](@ref), which pulls out all the terms that are matrix
terms as determined by the trait function [`is_matrix_term`](@ref), which is 
true by default for all `AbstractTerm`s.
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
    extract_matrix_terms(t::AbstractTerm) = extract_matrix_term((t, ))

Depending on whether the component terms are matrix terms (meaning they have
[`is_matrix_term(T) == true`](@ref is_matrix_term)), `extract_matrix_terms` will
return

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

"""
    model_cols(t::AbstractTerm, data)

Create a numerical "model columns" representation of data based on an
`AbstractTerm`.  `data` can either be a whole table or a single row (in the form
of a `NamedTuple` of scalar values).  Tables will be converted to a `NamedTuple`
of `Vectors` (e.g., a `Tables.ColumnTable`).
"""
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

"""
    coefnames(term::AbstractTerm)

Return the name[s] of columns generated by a term.  Return value is either a
`String` or an iterable of `String`s.
"""
StatsBase.coefnames(t::FormulaTerm) = (coefnames(t.lhs), coefnames(t.rhs))
StatsBase.coefnames(::InterceptTerm{H}) where {H} = H ? "(Intercept)" : []
StatsBase.coefnames(t::ContinuousTerm) = string(t.sym)
StatsBase.coefnames(t::CategoricalTerm) = 
    ["$(t.sym): $name" for name in t.contrasts.termnames]
StatsBase.coefnames(t::FunctionTerm) = string(t.exorig)
StatsBase.coefnames(ts::TupleTerm) = reduce(vcat, coefnames.(ts))
StatsBase.coefnames(t::MatrixTerm) = coefnames(t.terms)
StatsBase.coefnames(t::InteractionTerm) =
    kron_insideout((args...) -> join(args, " & "), vectorize.(coefnames.(t.terms))...)

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
"""
    term(xs...)

Wrap arguments in an appropriate `AbstractTerm` type: `Symbol`s become `Term`s,
and `Number`s become `ConstantTerm`s.  Any `AbstractTerm`s are unchanged.

# Example

```julia-repl
julia> ts = term(1, :a, :b)
1 + a + b

julia> typeof(ts)
Tuple{ConstantTerm{Int64},Term,Term}
```
"""
term(n::Number) = ConstantTerm(n)
term(s::Symbol) = Term(s)
term(args...) = term.(args)
term(t::AbstractTerm) = t
