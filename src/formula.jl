# Formulas for representing and working with linear-model-type expressions
# Original by Harlan D. Harris.  Later modifications by John Myles White,
# Douglas M. Bates, and other contributors.

## Formulas are written as expressions and parsed by the Julia parser.
## For example :(y ~ a + b + log(c))
## In Julia the & operator is used for an interaction.  What would be written
## in R as y ~ a + b + a:b is written :(y ~ a + b + a&b) in Julia.
## The equivalent R expression, y ~ a*b, is the same in Julia

## The lhs of a one-sided formula is 'nothing'
## The rhs of a formula can be 1

is_call(ex::Expr) = Meta.isexpr(ex, :call)
is_call(ex::Expr, op::Symbol) = Meta.isexpr(ex, :call) && ex.args[1] == op
is_call(::Any) = false
is_call(::Any, ::Any) = false
check_call(ex) = is_call(ex) || throw(ArgumentError("non-call expression encountered: $ex"))

catch_dollar(ex::Expr) =
    Meta.isexpr(ex, :$) && throw(ArgumentError("interpolation with \$ not supported in @formula.  Use @eval @formula(...) instead."))

mutable struct Formula
    ex_orig::Expr
    ex::Expr
    lhs::Union{Symbol, Expr, Nothing}
    rhs::Union{Symbol, Expr, Integer}
end

"""
    @formula(ex)

Capture and parse a formula expression as a `Formula` struct.

A formula is an abstract specification of a dependence between _left-hand_ and
_right-hand_ side variables as in, e.g., a regression model.  Each side
specifies at a high level how tabular data is to be converted to a numerical
matrix suitable for modeling.  This specification looks something like Julia
code, is represented as a Julia `Expr`, but uses special syntax.  The `@formula`
macro takes an expression like `y ~ 1 + a*b`, transforms it according to the
formula syntax rules into a lowered form (like `y ~ 1 + a + b + a&b`), and
constructs a `Formula` struct which captures the original expression, the
lowered expression, and the left- and right-hand-side.

Operators that have special interpretations in this syntax are

* `~` is the formula separator, where it is a binary operator (the first
  argument is the left-hand side, and the second is the right-hand side.
* `+` concatenates variables as columns when generating a model matrix.
* `&` representes an _interaction_ between two or more variables, which
  corresponds to a row-wise kronecker product of the individual terms
  (or element-wise product if all terms involved are continuous/scalar).
* `*` expands to all main effects and interactions: `a*b` is equivalent to
  `a+b+a&b`, `a*b*c` to `a+b+c+a&b+a&c+b&c+a&b&c`, etc.
* `1`, `0`, and `-1` indicate the presence (for `1`) or absence (for `0` and
  `-1`) of an intercept column.

The rules that are applied are

* The associative rule (un-nests nested calls to `+`, `&`, and `*`).
* The distributive rule (interactions `&` distribute over concatenation `+`).
* The `*` rule expands `a*b` to `a+b+a&b` (recursively).
* Subtraction is converted to addition and negation, so `x-1` becomes `x + -1`
  (applies only to subtraction of literal 1).
* Single-argument `&` calls are stripped, so `&(x)` becomes the main effect `x`.
"""
macro formula(ex)
    try
        is_call(ex, :~) || throw(ArgumentError("expected formula separator ~, got $(ex.head)"))
        length(ex.args) == 3 ||  throw(ArgumentError("malformed expression in formula $ex"))
        ex_orig = Meta.quot(copy(ex))
        sort_terms!(parse!(ex))
        lhs = Meta.quot(ex.args[2])
        rhs = Meta.quot(ex.args[3])
        return Expr(:call, :Formula, ex_orig, Meta.quot(ex), lhs, rhs)
    catch e
        return :(throw($e))
    end
end

Base.:(==)(f1::Formula, f2::Formula) = all(getfield(f1, f)==getfield(f2, f) for f in fieldnames(typeof(f1)))

"""
Representation of parsed `Formula`

This is an internal type whose implementation is likely to change in the near
future.
"""
mutable struct Terms
    terms::Vector
    eterms::Vector        # evaluation terms
    factors::Matrix{Bool} # maps terms to evaluation terms
    ## An eterms x terms matrix which is true for terms that need to be "promoted"
    ## to full rank in constructing a model matrx
    is_non_redundant::Matrix{Bool}
# order can probably be dropped.  It is vec(sum(factors, 1))
    order::Vector{Int}    # orders of rhs terms
    response::Bool        # indicator of a response, which is eterms[1] if present
    intercept::Bool       # is there an intercept column in the model matrix?
end

Base.:(==)(t1::Terms, t2::Terms) = all(getfield(t1, f)==getfield(t2, f) for f in fieldnames(typeof(t1)))

function Base.show(io::IO, f::Formula)
    print(io, "Formula: ", something(f.lhs, ""), " ~ ", f.rhs)
end


"""
    abstract type FormulaRewrite end

Formula parsing is expressed as a bunch of expression re-writes, each of which
is a subtype of `FormulaRewrite`.  There are two methods that dispatch on these
types: `applies(ex, child_idx, rule::Type{<:FormulaRewrite})` checks whether the
re-write `rule` needs to be applied at argument `child_idx` of expression `ex`,
and `rewrite!(ex, child_idx, rule::Type{<:FormulaRewrite})` re-writes `ex`
according to `rule` at position `child_idx`, and returns the next `child_idx`
that needs to be checked.
"""
abstract type FormulaRewrite end

"""
    struct Star <: FormulaRewrite end

Expand `a*b` to `a + b + a&b` (`*(a,b)` to `+(a,b,&(a,b))`).  Applies
recursively to multiple `*` arguments, so needs a clean-up pass (from
distributive/associative).
"""
struct Star <: FormulaRewrite end
applies(ex::Expr, child_idx::Int, ::Type{Star}) = is_call(ex.args[child_idx], :*)
expand_star(a, b) = Expr(:call, :+, a, b, Expr(:call, :&, a, b))
function rewrite!(ex::Expr, child_idx::Int, ::Type{Star})
    child = ex.args[child_idx]
    @debug "  expand star: $ex -> "
    child.args = reduce(expand_star, child.args[2:end]).args
    @debug "               $ex"
    child_idx
end

"""
    struct AssociativeRule <: FormulaRewrite end

Apply associative rule: if in an expression headed by an associative operator
(`+,&,*`) and the sub-expression `child_idx` is headed by the same operator,
splice that child's children into it's location.
"""
struct AssociativeRule <: FormulaRewrite end
const ASSOCIATIVE = Set([:+, :&, :*])
applies(ex::Expr, child_idx::Int, ::Type{AssociativeRule}) =
    is_call(ex) &&
    is_call(ex.args[child_idx]) &&
    ex.args[1] in ASSOCIATIVE &&
    ex.args[1] == ex.args[child_idx].args[1]
function rewrite!(ex::Expr, child_idx::Int, ::Type{AssociativeRule})
    @debug "    associative: $ex -> "
    splice!(ex.args, child_idx, ex.args[child_idx].args[2:end])
    @debug "                 $ex"
    child_idx
end


"""
    struct Distributive <: FormulaRewrite end

Distributive propery: `&(a..., +(b...), c...)` to `+(&(a..., b_i, c...)_i...)`.
Replace outer call (:&) with inner call (:+), whose arguments are copies of the
outer call, one for each argument of the inner call.  For the ith new child, the
original inner call is replaced with the ith argument of the inner call.
"""
struct Distributive <: FormulaRewrite end
const DISTRIBUTIVE = Set([:& => :+])
applies(ex::Expr, child_idx::Int, ::Type{Distributive}) =
    is_call(ex) &&
    is_call(ex.args[child_idx]) &&
    (ex.args[1] => ex.args[child_idx].args[1]) in DISTRIBUTIVE
function rewrite!(ex::Expr, child_idx::Int, ::Type{Distributive})
    @debug "    distributive: $ex -> "
    new_args = deepcopy(ex.args[child_idx].args)
    for i in 2:length(new_args)
        new_child = deepcopy(ex)
        new_child.args[child_idx] = new_args[i]
        new_args[i] = new_child
    end
    ex.args = new_args
    @debug "                  $ex"
    # TODO: is it really necessary to re-check _every_argument after this?
    2
end

"""
    Subtraction <: FormulaRewrite

Correct `x - 1` to `x + -1`
"""
struct Subtraction <: FormulaRewrite end
applies(ex::Expr, child_idx::Int, ::Type{Subtraction}) =
    is_call(ex.args[child_idx], :-)
function rewrite!(ex::Expr, child_idx::Int, ::Type{Subtraction})
    child = ex.args[child_idx]
    child.args[3] == 1 || throw(ArgumentError("Can only subtract 1, got $child"))
    child.args[1] = :+
    child.args[3] = -1
    child_idx
end

"""
    And1 <: FormulaRewrite

Remove numbers from interaction terms, so `1&x` becomes `&(x)` (which is later 
cleaned up by `EmptyAnd`).
"""
struct And1 <: FormulaRewrite end
applies(ex::Expr, child_idx::Int, ::Type{And1}) =
    is_call(ex, :&) && ex.args[child_idx] isa Number
function rewrite!(ex::Expr, child_idx::Int, ::Type{And1})
    @debug "    &1: $ex ->"
    ex.args[child_idx] == 1 ||
        @warn "Number $(ex.args[child_idx]) removed from interaction term $ex"
    deleteat!(ex.args, child_idx)
    @debug "        $ex"
    child_idx
end

"""
    EmptyAnd <: FormulaRewrite

Convert single-argument interactions to symbols: `&(x)` to `x` (cleanup after
`And1`.
"""
struct EmptyAnd <: FormulaRewrite end
applies(ex::Expr, child_idx::Int, ::Type{EmptyAnd}) =
    is_call(ex.args[child_idx], :&) &&
    length(ex.args[child_idx].args) == 2
function rewrite!(ex::Expr, child_idx::Int, ::Type{EmptyAnd})
    ex.args[child_idx] = ex.args[child_idx].args[2]
    child_idx
end

# default re-write is a no-op (go to next child)
rewrite!(ex::Expr, child_idx::Int, ::Nothing) = child_idx+1

# like `findfirst` but returns the first element where predicate is true, or
# nothing
function filterfirst(f::Function, a::AbstractArray)
    idx = Compat.findfirst(f, a)
    idx === nothing ? nothing : a[idx]
end


parse!(x) = parse!(x, [And1, EmptyAnd, Subtraction, Star, AssociativeRule, Distributive])
parse!(x, rewrites) = x
function parse!(i::Integer, rewrites)
    i ∈ [-1, 0, 1] || throw(ArgumentError("invalid integer term $i (only -1, 0, and 1 allowed)"))
    i
end
function parse!(ex::Expr, rewrites::Vector)
    @debug "parsing $ex"
    catch_dollar(ex)
    check_call(ex)
    # iterate over children, checking for special rules
    child_idx = 2
    while child_idx <= length(ex.args)
        @debug "  ($(ex.args[1])) i=$child_idx: $(ex.args[child_idx])"
        # depth first: parse each child first
        parse!(ex.args[child_idx], rewrites)
        # find first rewrite rule that applies
        rule = filterfirst(r->applies(ex, child_idx, r), rewrites)
        # re-write according to that rule and update the child to position rewrite next
        child_idx = rewrite!(ex, child_idx, rule)
    end
    @debug "done: $ex"
    ex
end


function sort_terms!(ex::Expr)
    check_call(ex)
    if ex.args[1] ∈ ASSOCIATIVE
        sort!(view(ex.args, 2:length(ex.args)), by=degree)
    else
        # recursively sort children
        sort_terms!.(ex.args)
    end
    ex
end
sort_terms!(x) = x

degree(i::Integer) = 0
degree(::Symbol) = 1
function degree(ex::Expr)
    check_call(ex)
    if ex.args[1] == :&
        length(ex.args) - 1
    elseif ex.args[1] == :|
        # put ranef terms at end
        typemax(Int)
    else
        # arbitrary functions are treated as main effect terms
        1
    end
end


################################################################################



## always return an ARRAY of terms
getterms(ex::Expr) = is_call(ex, :+) ? ex.args[2:end] : Expr[ex]
getterms(a::Any) = Any[a]

const nonevaluation = Set([:&,:|])        # operators constructed from other evaluations
## evaluation terms - the (filtered) arguments for :& and :|, otherwise the term itself
function evt(ex::Expr)
    check_call(ex)
    if !(ex.args[1] in nonevaluation) return ex end
    filter(x->!isa(x,Number), vcat(map(getterms, ex.args[2:end])...))
end
evt(a) = Any[a]

function Terms(f::Formula)
    rhs = f.rhs
    tt = unique(getterms(rhs))
    filter!(t -> t != 1, tt)                          # drop any explicit 1's
    noint = BitArray(map(t -> t == 0 || t == -1, tt)) # should also handle :(-(expr,1))
    tt = tt[map(!, noint)]
    oo = Int[degree(t) for t in tt] # orders of interaction terms
    if !issorted(oo)                # sort terms by increasing order
        pp = sortperm(oo)
        tt = tt[pp]
        oo = oo[pp]
    end
    etrms = map(evt, tt)
    haslhs = f.lhs != nothing
    if haslhs
        pushfirst!(etrms, Any[f.lhs])
        pushfirst!(oo, 1)
    end
    ev = unique(vcat(etrms...))
    sets = [Set(x) for x in etrms]
    facs = Bool[t in s for t in ev, s in sets]
    non_redundants = fill(false, size(facs)) # initialize to false
    Terms(tt, ev, facs, non_redundants, oo, haslhs, !any(noint))
end


"""
    Formula(t::Terms)

Reconstruct a Formula from Terms.
"""
function Formula(t::Terms)
    lhs = t.response ? t.eterms[1] : nothing
    rhs = Expr(:call,:+)
    if t.intercept
        push!(rhs.args,1)
    end
    append!(rhs.args,t.terms)
    ex = :($lhs ~ $rhs)
    Formula(ex, ex, lhs,rhs)
end

copyside(s) = copy(s)
copyside(s::Symbol) = s

function Base.copy(f::Formula)
    return Formula(copy(f.ex_orig), copy(f.ex), copyside(f.lhs), copyside(f.rhs))
end

"""
    dropterm(f::Formula, trm::Symbol)

Return a copy of `f` without the term `trm`.

# Examples
```jl
julia> dropterm(@formula(foo ~ 1 + bar + baz), :bar)
Formula: foo ~ 1 + baz

julia> dropterm(@formula(foo ~ 1 + bar + baz), 1)
Formula: foo ~ 0 + bar + baz
```
"""
dropterm(f::Formula, trm::Union{Number, Symbol, Expr}) = dropterm!(copy(f), trm)

function dropterm!(f::Formula, trm::Union{Number, Symbol, Expr})
    rhs = f.rhs
    if !(is_call(rhs, :+) && (tpos = Compat.findlast(isequal(trm), rhs.args)) !== nothing)
        throw(ArgumentError("$trm is not a summand of '$(f.rhs)'"))
    end
    if isa(trm, Number)
        if trm ≠ one(trm)
            throw(ArgumentError("Cannot drop $trm from a formula"))
        end
        rhs.args[tpos] = 0
    else
        deleteat!(rhs.args, [tpos])
    end
    return f
end
