# Formulas for representing and working with linear-model-type expressions
# Original by Harlan D. Harris.  Later modifications by John Myles White,
# Douglas M. Bates, and other contributors.

## Formulas are written as expressions and parsed by the Julia parser.
## For example :(y ~ a + b + log(c))
## In Julia the & operator is used for an interaction.  What would be written
## in R as y ~ a + b + a:b is written :(y ~ a + b + a&b) in Julia.
## The equivalent R expression, y ~ a*b, is the same in Julia

## The lhs of a one-sided formula is 0
## The rhs of a formula can be 1

is_call(ex::Expr) = Meta.isexpr(ex, :call)
is_call(ex::Expr, op::Symbol) = Meta.isexpr(ex, :call) && ex.args[1] == op
is_call(::Any) = false
is_call(::Any, ::Any) = false
check_call(ex) = is_call(ex) || throw(ArgumentError("non-call expression encountered: $ex"))

catch_dollar(ex::Expr) =
    Meta.isexpr(ex, :$) && throw(ArgumentError("interpolation with \$ not supported in @formula.  Use @eval @formula(...) instead."))

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
    terms!(parse!(ex))
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
const ASSOCIATIVE = (:+, :&, :*)
applies(ex::Expr, child_idx::Int, ::Type{AssociativeRule}) =
    is_call(ex) &&
    ex.args[1] in ASSOCIATIVE &&
    is_call(ex.args[child_idx], ex.args[1])
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

# default re-write is a no-op (go to next child)
rewrite!(ex::Expr, child_idx::Int, ::Nothing) = child_idx+1

# like `findfirst` but returns the first element where predicate is true, or
# nothing
function filterfirst(f::Function, a::AbstractArray)
    idx = findfirst(f, a)
    idx === nothing ? nothing : a[idx]
end

const SPECIALS = (:+, :&, :*, :~)

parse!(x) = parse!(x, [Star])
parse!(x, rewrites) = x
function parse!(ex::Expr, rewrites::Vector)
    @debug "parsing $ex"
    catch_dollar(ex)
    check_call(ex)

    # don't recurse into captured calls
    if is_call(ex, :capture_call) || is_call(ex, :(StatsModels.capture_call))
        @debug "  skipping capture_call"
        return ex
    end

    # parse a copy of non-special calls
    ex_parsed = ex.args[1] ∉ SPECIALS ? deepcopy(ex) : ex
    
    # iterate over children, checking for special rules
    child_idx = 2
    while child_idx <= length(ex_parsed.args)
        @debug "  ($(ex_parsed.args[1])) i=$child_idx: $(ex_parsed.args[child_idx])"
        # depth first: parse each child first
        parse!(ex_parsed.args[child_idx], rewrites)
        # find first rewrite rule that applies
        rule = filterfirst(r->applies(ex_parsed, child_idx, r), rewrites)
        # re-write according to that rule and update the child to position rewrite nex_parsedt
        child_idx = rewrite!(ex_parsed, child_idx, rule)
    end
    @debug "done: $ex_parsed"

    if ex.args[1] ∈ SPECIALS
        return ex_parsed
    else
        @debug "  capturing non-special call $ex"
        return capture_call_ex!(ex, ex_parsed)
    end
end

"""
    capture_call_ex!(ex::Expr, ex_parsed::Expr)

Capture a call to a function that is not part of the formula DSL.  This replaces
`ex` with a call to [`capture_call`](@ref).  `ex_parsed` is a copy of `ex` whose
arguments have been parsed according to the normal formula DSL rules and which 
will be passed as the final argument to `capture_call`.
"""
function capture_call_ex!(ex::Expr, ex_parsed::Expr)
    symbols = extract_symbols(ex)
    symbols_ex = Expr(:tuple, symbols...)
    f_anon_ex = esc(Expr(:(->), symbols_ex, copy(ex)))
    f_orig = ex.args[1]
    ex.args = [:capture_call,
               esc(f_orig),
               f_anon_ex,
               tuple(symbols...),
               Meta.quot(deepcopy(ex)),
               :[$(ex_parsed.args[2:end]...)]]
    return ex
end


# generate Term expressions for symbols (including parsed args of non-special calls
terms!(::Nothing) = :(nothing)
terms!(s::Symbol) = :(Term($(Meta.quot(s))))
terms!(n::Number) = :(ConstantTerm($n))
function terms!(ex::Expr)
    if ex.args[1] ∈ SPECIALS
        ex.args[1] = esc(ex.args[1])
        ex.args[2:end] .= terms!.(ex.args[2:end])
    elseif is_call(ex, :capture_call)
        # final argument of capture_call holds parsed terms
        ex.args[end].args .= terms!.(ex.args[end].args)
    end
    return ex
end
