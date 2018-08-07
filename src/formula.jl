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
    is_call(ex, :~) || throw(ArgumentError("expected formula separator ~, got $(ex.head)"))
    length(ex.args) == 3 ||  throw(ArgumentError("malformed expression in formula $ex"))
    ex |> parse! |> sort_terms! |> terms!
end

Base.:(==)(f1::Formula, f2::Formula) = all(getfield(f1, f)==getfield(f2, f) for f in fieldnames(typeof(f1)))

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

const SPECIALS = Set([:+, :&, :*, :~])
"""
    is_special(s)
    is_special(::Val{s}) where s

Return `true` if arguments to calls to `s` should be treated as `Term`s, and
`false` as normal julia code.  `is_special(s::Symbol)` falls back to
`is_special(::Val{s})`, so to treat calls to `myfun` as special formula syntax
define `is_special(::Val{:myfun}) = true`.
"""
is_special(s::Symbol) = s ∈ SPECIALS || is_special(Val(s))
is_special(s) = false


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
    # if not a "special call", then create an anonymous function, and don't recurse
    if is_special(ex.args[1])
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
end

# generate Term expressions for symbols and FormulaTerms for non-special calls
terms!(::Nothing) = :(nothing)
terms!(s::Symbol) = :(Term($(Meta.quot(s))))
terms!(i::Integer) = :(InterceptTerm{$(i==1)}())
function terms!(ex::Expr)
    if is_special(ex.args[1])
        ex.args[2:end] .= terms!.(ex.args[2:end])
    else
        @debug "  generating anonymous function for $ex"
        capture_call_ex!(ex)
    end
    return ex
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
