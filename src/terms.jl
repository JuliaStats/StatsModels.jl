abstract type AbstractTerm end
const TermOrTerms = Union{AbstractTerm, NTuple{N, AbstractTerm} where N}
const TupleTerm = NTuple{N, TermOrTerms} where N

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
width(::Term) =
    throw(ArgumentError("Un-typed Terms have undefined width.  " *
                        "Did you forget to call apply_schema?"))

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
width(::ConstantTerm) = 1

"""
    FormulaTerm{L,R} <: AbstractTerm

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

"""
    FunctionTerm{Forig,Fanon,Names} <: AbstractTerm

Represents a call to a Julia function.  The first type parameter is the type
of the function as originally specified (e.g., `typeof(log)`), while the second
is the type of the anonymous function that will be applied element-wise to the
data table.

The `FunctionTerm` _also_ captures the arguments of the original call and parses
them _as if_ they were part of a special DSL call, applying the rules to expand
`*`, distribute `&` over `+`, and wrap symbols in `Term`s.  

By storing the original function as a type parameter _and_ pessimistically
parsing the arguments as if they're part of a special DSL call, this allows
custom syntax to be supported with minimal extra effort.  Packages can dispatch
on `apply_schema(f::FunctionTerm{typeof(special_syntax)}, schema,
::Type{<:MyModel})` and pull out the arguments parsed as terms from
`f.args_parsed` to construct their own custom terms.

# Fields

* `forig::Forig`: the original function (e.g., `log`)
* `fanon::Fanon`: the generated anonymous function (e.g., `(a, b) -> log(1+a+b)`)
* `exorig::Expr`: the original expression passed to `@formula`
* `args_parsed::Vector`: the arguments of the call passed to `@formula`, each 
  parsed _as if_ the call was a "special" DSL call.

# Type parameters

* `Forig`: the type of the original function (e.g., `typeof(log)`)
* `Fanon`: the type of the generated anonymous function
* `Names`: the names of the arguments to the anonymous function (as a
  `NTuple{N,Symbol}`)

# Example

```jldoctest
julia> f = @formula(y ~ log(1 + a + b))
FormulaTerm
Response:
  y(unknown)
Predictors:
  (a,b)->log(1 + a + b)

julia> typeof(f.rhs)
FunctionTerm{typeof(log),var"##1#2",(:a, :b)}

julia> f.rhs.forig(1 + 3 + 4)
2.0794415416798357

julia> f.rhs.fanon(3, 4)
2.0794415416798357

julia> modelcols(f.rhs, (a=3, b=4))
2.0794415416798357

julia> modelcols(f.rhs, (a=[3, 4], b=[4, 5]))
2-element Array{Float64,1}:
 2.0794415416798357
 2.302585092994046 
```
"""
struct FunctionTerm{Forig,Fanon,Names} <: AbstractTerm
    forig::Forig
    fanon::Fanon
    exorig::Expr
    args_parsed::Vector
end
FunctionTerm(forig::Fo, fanon::Fa, names::NTuple{N,Symbol},
             exorig::Expr, args_parsed) where {Fo,Fa,N}  =
    FunctionTerm{Fo, Fa, names}(forig, fanon, exorig, args_parsed)
width(::FunctionTerm) = 1

"""
    InteractionTerm{Ts} <: AbstractTerm

Represents an _interaction_ between two or more individual terms.  

Generated by combining multiple `AbstractTerm`s with `&` (which is what calls to
`&` in a `@formula` lower to)

# Fields

* `terms::Ts`: the terms that participate in the interaction.

# Example

```jldoctest
julia> d = (y = rand(9), a = 1:9, b = rand(9), c = repeat(["d","e","f"], 3));

julia> t = InteractionTerm(term.((:a, :b, :c)))
a(unknown) & b(unknown) & c(unknown)

julia> t == term(:a) & term(:b) & term(:c)
true

julia> t = apply_schema(t, schema(d))
a(continuous) & b(continuous) & c(DummyCoding:3→2)

julia> modelcols(t, d)
9×2 Array{Float64,2}:
 0.0      0.0    
 1.09793  0.0    
 0.0      2.6946 
 0.0      0.0    
 4.67649  0.0    
 0.0      4.47245
 0.0      0.0    
 0.64805  0.0    
 0.0      6.97926

julia> modelcols(t.terms, d)
([1, 2, 3, 4, 5, 6, 7, 8, 9], [0.8865801492659497, 0.5489667874821704, 0.8981985570141182, 0.5043129521484462, 0.9352977047074365, 0.7454079139997376, 0.4898716849925324, 0.08100620947201143, 0.7754728346104993], [0.0 0.0; 1.0 0.0; … ; 1.0 0.0; 0.0 1.0])
```
"""
struct InteractionTerm{Ts} <: AbstractTerm
    terms::Ts
end
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
width(::InterceptTerm{H}) where {H} = H ? 1 : 0

# Typed terms

"""
    ContinuousTerm <: AbstractTerm

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
width(::ContinuousTerm) = 1

"""
    CategoricalTerm{C,T,N} <: AbstractTerm

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
width(::CategoricalTerm{C,T,N}) where {C,T,N} = N

# constructor that computes the width based on the contrasts matrix
CategoricalTerm(sym::Symbol, contrasts::ContrastsMatrix{C,T}) where {C,T} =
    CategoricalTerm{C,T,length(contrasts.termnames)}(sym, contrasts)

"""
    MatrixTerm{Ts} <: AbstractTerm

A collection of terms that should be combined to produce a single numeric matrix.

A matrix term is created by [`apply_schema`](@ref) from a tuple of terms using 
[`collect_matrix_terms`](@ref), which pulls out all the terms that are matrix
terms as determined by the trait function [`is_matrix_term`](@ref), which is 
true by default for all `AbstractTerm`s.
"""
struct MatrixTerm{Ts<:TupleTerm} <: AbstractTerm
    terms::Ts
end
# wrap single terms in a tuple
MatrixTerm(t::AbstractTerm) = MatrixTerm((t, ))
width(t::MatrixTerm) = sum(width(tt) for tt in t.terms)

"""
    collect_matrix_terms(ts::TupleTerm)
    collect_matrix_terms(t::AbstractTerm) = collect_matrix_term((t, ))

Depending on whether the component terms are matrix terms (meaning they have
[`is_matrix_term(T) == true`](@ref is_matrix_term)), `collect_matrix_terms` will
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
function collect_matrix_terms(ts::TupleTerm)
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
collect_matrix_terms(t::T) where {T<:AbstractTerm} =
    is_matrix_term(T) ? MatrixTerm((t, )) : t
collect_matrix_terms(t::MatrixTerm) = t


"""
    is_matrix_term(::Type{<:AbstractTerm})

Does this type of term get concatenated with other matrix terms into a single
model matrix?  This controls the behavior of the [`collect_matrix_terms`](@ref),
which collects all of its arguments for which `is_matrix_term` returns `true`
into a [`MatrixTerm`](@ref), and returns the rest unchanged.

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
part of the DSL, it replaces the expression with a call to `capture_call` that
captures captures the original function called, an anonymous function that can
be applied row-wise to a table, and the arguments of the original call parsed as
if they were part of the formula.

The call to `capture_call` is generated by [`capture_call_ex!`](@ref), and just
calls passes its arguments to the [`FunctionTerm`](@ref) constructor.
"""
capture_call(args...) = FunctionTerm(args...)

extract_symbols(x) = Symbol[]
extract_symbols(x::Symbol) = [x]
extract_symbols(ex::Expr) =
    is_call(ex) ? mapreduce(extract_symbols, union, ex.args[2:end]) : Symbol[]

################################################################################
# showing terms

function Base.show(io::IO, mime::MIME"text/plain", term::AbstractTerm; prefix="")
    print(io, prefix, term)
end

function Base.show(io::IO, mime::MIME"text/plain", terms::TupleTerm; prefix=nothing)
    for t in terms
        show(io, mime, t; prefix=something(prefix, ""))
        # ensure that there are newlines in between each term after the first
        # if no prefix is specified
        prefix = something(prefix, '\n')
    end
end
Base.show(io::IO, terms::TupleTerm) = join(io, terms, " + ")

Base.show(io::IO, ::MIME"text/plain", t::Term; prefix="") =
    print(io, prefix, t.sym, "(unknown)")
Base.show(io::IO, t::Term) = print(io, t.sym)

Base.show(io::IO, t::ConstantTerm) = print(io, t.n)

Base.show(io::IO, t::FormulaTerm) = print(io, "$(t.lhs) ~ $(t.rhs)")
function Base.show(io::IO, mime::MIME"text/plain", t::FormulaTerm; prefix="")
    println(io, "FormulaTerm")
    print(io, "Response:")
    show(io, mime, t.lhs, prefix="\n  ")
    println(io)
    print(io, "Predictors:")
    show(io, mime, t.rhs, prefix="\n  ")
end

Base.show(io::IO, t::FunctionTerm) = print(io, ":($(t.exorig))")
function Base.show(io::IO, ::MIME"text/plain",
                   t::FunctionTerm{Fo,Fa,names};
                   prefix = "") where {Fo,Fa,names}
    print(io, prefix, "(")
    join(io, names, ",")
    print(io, ")->", t.exorig)
end

Base.show(io::IO, it::InteractionTerm) = join(io, it.terms, " & ")
function Base.show(io::IO, mime::MIME"text/plain", it::InteractionTerm; prefix="")
    for t in it.terms
        show(io, mime, t; prefix=prefix)
        prefix = " & "
    end
end

Base.show(io::IO, t::InterceptTerm{H}) where {H} = print(io, H ? "1" : "0")

Base.show(io::IO, t::ContinuousTerm) = print(io, t.sym)
Base.show(io::IO, ::MIME"text/plain", t::ContinuousTerm; prefix="") =
    print(io, prefix, t.sym, "(continuous)")

Base.show(io::IO, t::CategoricalTerm{C,T,N}) where {C,T,N} = print(io, t.sym)
Base.show(io::IO, ::MIME"text/plain", t::CategoricalTerm{C,T,N}; prefix="") where {C,T,N} =
    print(io, prefix, t.sym, "($C:$(length(t.contrasts.levels))→$N)")

Base.show(io::IO, t::MatrixTerm) = show(io, t.terms)
Base.show(io::IO, mime::MIME"text/plain", t::MatrixTerm; prefix="") =
    show(io, mime, t.terms, prefix=prefix)

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
    modelcols(t::AbstractTerm, data)

Create a numerical "model columns" representation of data based on an
`AbstractTerm`.  `data` can either be a whole table (a property-accessible
collection of iterable columns or iterable collection of property-accessible
rows, as defined by [Tables.jl](https://github.com/JuliaData/Tables.jl) or a
single row (in the form of a `NamedTuple` of scalar values).  Tables will be
converted to a `NamedTuple` of `Vectors` (e.g., a `Tables.ColumnTable`).
"""
function modelcols(t, d::D) where D
    Tables.istable(d) || throw(ArgumentError("Data of type $D is not a table!"))
    ## throw an error for t which don't have a more specific modelcols method defined
    ## TODO: this seems like it ought to be handled by dispatching on something
    ## like modelcols(::Any, ::NamedTuple) or modelcols(::AbstractTerm, ::NamedTuple)
    ## but that causes ambiguity errors or under-constrained modelcols methods for
    ## custom term types...
    d isa NamedTuple && throw(ArgumentError("don't know how to generate modelcols for " *
                                            "term $t. Did you forget to call apply_schema?"))
    modelcols(t, columntable(d))
end

"""
    modelcols(ts::NTuple{N, AbstractTerm}, data) where N

When a tuple of terms is provided, `modelcols` broadcasts over the individual 
terms.  To create a single matrix, wrap the tuple in a [`MatrixTerm`](@ref).

# Example

```jldoctest
julia> d = (a = [1:9;], b = rand(9), c = repeat(["d","e","f"], 3));

julia> ts = apply_schema(term.((:a, :b, :c)), schema(d))
a(continuous) 
b(continuous)
c(DummyCoding:3→2)

julia> cols = modelcols(ts, d)
([1, 2, 3, 4, 5, 6, 7, 8, 9], [0.7184176729016183, 0.4881665815778522, 0.7081609847641785, 0.7743011281211944, 0.584295963367869, 0.32493666547553657, 0.9894077965577408, 0.3331747574477202, 0.6532298571732302], [0.0 0.0; 1.0 0.0; … ; 1.0 0.0; 0.0 1.0])

julia> reduce(hcat, cols)
9×4 Array{Float64,2}:
 1.0  0.718418  0.0  0.0
 2.0  0.488167  1.0  0.0
 3.0  0.708161  0.0  1.0
 4.0  0.774301  0.0  0.0
 5.0  0.584296  1.0  0.0
 6.0  0.324937  0.0  1.0
 7.0  0.989408  0.0  0.0
 8.0  0.333175  1.0  0.0
 9.0  0.65323   0.0  1.0

julia> modelcols(MatrixTerm(ts), d)
9×4 Array{Float64,2}:
 1.0  0.718418  0.0  0.0
 2.0  0.488167  1.0  0.0
 3.0  0.708161  0.0  1.0
 4.0  0.774301  0.0  0.0
 5.0  0.584296  1.0  0.0
 6.0  0.324937  0.0  1.0
 7.0  0.989408  0.0  0.0
 8.0  0.333175  1.0  0.0
 9.0  0.65323   0.0  1.0
```
"""
modelcols(ts::TupleTerm, d::NamedTuple) = modelcols.(ts, Ref(d))

modelcols(t::Term, d::NamedTuple) =
    throw(ArgumentError("can't generate modelcols for un-typed term $t. " *
                        "Use apply_schema to create concrete terms first"))

# TODO: @generated to unroll the getfield stuff
modelcols(ft::FunctionTerm{Fo,Fa,Names}, d::NamedTuple) where {Fo,Fa,Names} =
    ft.fanon.(getfield.(Ref(d), Names)...)

modelcols(t::ContinuousTerm, d::NamedTuple) = copy.(d[t.sym])

modelcols(t::CategoricalTerm, d::NamedTuple) = t.contrasts[d[t.sym], :]


"""
    reshape_last_to_i(i::Int, a)

Reshape `a` so that its last dimension moves to dimension `i` (+1 if `a` is an 
`AbstractMatrix`).  
"""
reshape_last_to_i(i, a) = a
reshape_last_to_i(i, a::AbstractVector) = reshape(a, ones(Int, i-1)..., :)
reshape_last_to_i(i, a::AbstractMatrix) = reshape(a, size(a,1), ones(Int, i-1)..., :)

# an "inside out" kronecker-like product based on broadcasting reshaped arrays
# for a single row, some will be scalars, others possibly vectors.  for a whole
# table, some will be vectors, possibly some matrices
function kron_insideout(op::Function, args...)
    args = (reshape_last_to_i(i,a) for (i,a) in enumerate(args))
    vec(broadcast(op, args...))
end

function row_kron_insideout(op::Function, args...)
    rows = size(args[1], 1)
    args = (reshape_last_to_i(i,reshape(a, size(a,1), :)) for (i,a) in enumerate(args))
    # args = (reshape(a, size(a,1), ones(Int, i-1)..., :) for (i,a) in enumerate(args))
    reshape(broadcast(op, args...), rows, :)
end

# two options here: either special-case ColumnTable (named tuple of vectors)
# vs. vanilla NamedTuple, or reshape and use normal broadcasting
modelcols(t::InteractionTerm, d::NamedTuple) =
    kron_insideout(*, (modelcols(term, d) for term in t.terms)...)

function modelcols(t::InteractionTerm, d::ColumnTable)
    row_kron_insideout(*, (modelcols(term, d) for term in t.terms)...)
end

modelcols(t::InterceptTerm{true}, d::NamedTuple) = ones(size(first(d)))
modelcols(t::InterceptTerm{false}, d) = Matrix{Float64}(undef, size(first(d),1), 0)

modelcols(t::FormulaTerm, d::NamedTuple) = (modelcols(t.lhs,d), modelcols(t.rhs, d))

function modelcols(t::MatrixTerm, d::ColumnTable)
    mat = reduce(hcat, [modelcols(tt, d) for tt in t.terms])
    reshape(mat, size(mat, 1), :)
end

modelcols(t::MatrixTerm, d::NamedTuple) =
    reduce(vcat, [modelcols(tt, d) for tt in t.terms])

vectorize(x::Tuple) = collect(x)
vectorize(x::AbstractVector) = x
vectorize(x) = [x]

"""
    coefnames(term::AbstractTerm)

Return the name(s) of column(s) generated by a term.  Return value is either a
`Symbol` or an iterable of `String`s.
"""
StatsBase.coefnames(t::Term) = t.sym
StatsBase.coefnames(t::FormulaTerm) = (coefnames(t.lhs), coefnames(t.rhs))
StatsBase.coefnames(::InterceptTerm{H}) where {H} = H ? Symbol(:Intercept) : []  # this seems like the wrong thing to return
StatsBase.coefnames(t::ContinuousTerm) = t.sym
StatsBase.coefnames(t::CategoricalTerm) = [Symbol("$(t.sym): $name") for name in t.contrasts.termnames]
StatsBase.coefnames(t::FunctionTerm) = Symbol(string(t.exorig))
StatsBase.coefnames(t::MatrixTerm) = mapreduce(coefnames, vcat, t.terms)
#function StatsBase.coefnames(t::InteractionTerm)
#    Symbol.(kron_insideout((args...) -> join(args, " & "), vectorize.(coefnames.(t.terms))...))
#end
StatsBase.coefnames(t::InteractionTerm) =
    Symbol.(kron_insideout((args...) -> join(args, " & "), vectorize.(coefnames.(t.terms))...))
StatsBase.coefnames(ts::TupleTerm) = _coefnames(ts.terms)
_coefnames(ts::Tuple) = (coefnames(first(ts)), _coefnames(tail(ts))...)
_coefnames(ts::Tuple{}) = ()

"""
    coef(term::AbstractTerm, s::Symbol)
"""
function StatsBase.coef(f::FormulaTerm, s::Symbol)
    if coefname(f.lhs) === s
        c = f.lhs
    else
        c = _coef(f.rhs, s)
    end
    if c isa AbstractTerm
        return c
    else
        error("$c is not a coefficient within $term")
    end
end
_coef(t::AbstractTerm, s::Symbol) = coefnames(t) === s ? t : false
function _coef(t::MatrixTerm, s::Symbol)
    for t_i in t
        coefname(t_i) === s && return t_i
    end
    return false
end



################################################################################
# old Terms features:

hasintercept(f::FormulaTerm) = hasintercept(f.rhs)
hasintercept(t::TermOrTerms) =
    InterceptTerm{true}() ∈ terms(t) ||
    ConstantTerm(1) ∈ terms(t)
omitsintercept(f::FormulaTerm) = omitsintercept(f.rhs)
omitsintercept(t::TermOrTerms) =
    InterceptTerm{false}() ∈ terms(t) ||
    ConstantTerm(0) ∈ terms(t) ||
    ConstantTerm(-1) ∈ terms(t)

hasresponse(t) = false
hasresponse(t::FormulaTerm) =
    t.lhs !== nothing && 
    t.lhs !== ConstantTerm(0) &&
    t.lhs !== InterceptTerm{false}()

# convenience converters
"""
    term(x)

Wrap argument in an appropriate `AbstractTerm` type: `Symbol`s become `Term`s,
and `Number`s become `ConstantTerm`s.  Any `AbstractTerm`s are unchanged.

# Example

```jldoctest
julia> ts = term.((1, :a, :b))
1
a(unknown)
b(unknown)

julia> typeof(ts)
Tuple{ConstantTerm{Int64},Term,Term}
```
"""
term(n::Number) = ConstantTerm(n)
term(s::Symbol) = Term(s)
term(t::AbstractTerm) = t
