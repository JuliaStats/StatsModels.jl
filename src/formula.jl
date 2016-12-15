# Formulas for representing and working with linear-model-type expressions
# Original by Harlan D. Harris.  Later modifications by John Myles White,
# Douglas M. Bates, and other contributors.

## Formulas are written as expressions and parsed by the Julia parser.
## For example :(y => a + b + log(c))
## In Julia the & operator is used for an interaction.  What would be written
## in R as y ~ a + b + a:b is written :(y => a + b + a&b) in Julia.
## The equivalent R expression, y ~ a*b, is the same in Julia

## The lhs of a one-sided formula is 'nothing'
## The rhs of a formula can be 1

type Formula
    lhs::Union{Symbol, Expr, Void}
    rhs::Union{Symbol, Expr, Integer}
end

macro model(formula)
    formula.head === :(=>) || error("expected formula separator =>, got $(formula.head)")
    length(formula.args) == 2 || error("malformed expression in formula")
    lhs = Base.Meta.quot(formula.args[1])
    rhs = Base.Meta.quot(formula.args[2])
    return Expr(:call, :Formula, lhs, rhs)
end

"""
Representation of parsed `Formula`

This is an internal type whose implementation is likely to change in the near
future.
"""
type Terms
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

Base.:(==)(t1::Terms, t2::Terms) = all(getfield(t1, f)==getfield(t2, f) for f in fieldnames(t1))

function Base.show(io::IO, f::Formula)
    print(io, "Formula: ", f.lhs === nothing ? "" : f.lhs, " => ", f.rhs)
end

# special operators in formulas
const specials = Set([:+, :-, :*, :/, :&, :|, :^])

function dospecials(ex::Expr)
    if ex.head != :call error("Non-call expression encountered") end
    a1 = ex.args[1]
    if !(a1 in specials) return ex end
    excp = copy(ex)
    excp.args = vcat(a1,map(dospecials, ex.args[2:end]))
    if a1 == :-
        a2, a3 = excp.args[2:3]
        a3 == 1 || error("invalid expression $ex; subtraction only supported for -1")
        return :($a2 + -1)
    elseif a1 == :*
        aa = excp.args
        a2 = aa[2]
        a3 = aa[3]
        if length(aa) > 3
            excp.args = vcat(a1, aa[3:end])
            a3 = dospecials(excp)
        end
        ## this order of expansion gives the R-style ordering of interaction
        ## terms (after sorting in increasing interaction order) for higher-
        ## order interaction terms (e.g. x1 * x2 * x3 should expand to x1 +
        ## x2 + x3 + x1&x2 + x1&x3 + x2&x3 + x1&x2&x3)
        :($a2 + $a2 & $a3 + $a3)
    else
        excp
    end
end
dospecials(a::Any) = a

## Distribution of & over +
const distributive = @compat Dict(:& => :+)

distribute(ex::Expr) = distribute!(copy(ex))
distribute(a::Any) = a
## apply distributive property in-place
function distribute!(ex::Expr)
    if ex.head != :call error("Non-call expression encountered") end
    [distribute!(a) for a in ex.args[2:end]]
    ## check that top-level can be distributed
    a1 = ex.args[1]
    if a1 in keys(distributive)

        ## which op is being DISTRIBUTED (e.g. &, *)?
        distributed_op = a1
        ## which op is doing the distributing (e.g. +)?
        distributing_op = distributive[a1]

        ## detect distributing sub-expression (first arg is, e.g. :+)
        is_distributing_subex(e) =
            typeof(e)==Expr && e.head == :call && e.args[1] == distributing_op

        ## find first distributing subex
        first_distributing_subex = findfirst(is_distributing_subex, ex.args)
        if first_distributing_subex != 0
            ## remove distributing subexpression from args
            subex = splice!(ex.args, first_distributing_subex)

            newargs = Any[distributing_op]
            ## generate one new sub-expression, which calls the distributed operation
            ## (e.g. &) on each of the distributing sub-expression's arguments, plus
            ## the non-distributed arguments of the original expression.
            for a in subex.args[2:end]
                new_subex = copy(ex)
                push!(new_subex.args, a)
                ## need to recurse here, in case there are any other
                ## distributing operations in the sub expression
                distribute!(new_subex)
                push!(newargs, new_subex)
            end
            ex.args = newargs
        end
    end
    ex
end
distribute!(a::Any) = a

const associative = Set([:+,:*,:&])       # associative special operators

## If the expression is a call to the function s return its arguments
## Otherwise return the expression
function ex_or_args(ex::Expr,s::Symbol)
    if ex.head != :call error("Non-call expression encountered") end
    if ex.args[1] == s
        ## recurse in case there are more :calls of s below
        return vcat(map(x -> ex_or_args(x, s), ex.args[2:end])...)
    else
        ## not a :call to s, return condensed version of ex
        return condense(ex)
    end
end
ex_or_args(a,s::Symbol) = a

## Condense calls like :(+(a,+(b,c))) to :(+(a,b,c))
function condense(ex::Expr)
    if ex.head != :call error("Non-call expression encountered") end
    a1 = ex.args[1]
    if !(a1 in associative) return ex end
    excp = copy(ex)
    excp.args = vcat(a1, map(x->ex_or_args(x,a1), ex.args[2:end])...)
    excp
end
condense(a::Any) = a

## always return an ARRAY of terms
getterms(ex::Expr) = (ex.head == :call && ex.args[1] == :+) ? ex.args[2:end] : Expr[ex]
getterms(a::Any) = Any[a]

ord(ex::Expr) = (ex.head == :call && ex.args[1] == :&) ? length(ex.args)-1 : 1
ord(a::Any) = 1

const nonevaluation = Set([:&,:|])        # operators constructed from other evaluations
## evaluation terms - the (filtered) arguments for :& and :|, otherwise the term itself
function evt(ex::Expr)
    if ex.head != :call error("Non-call expression encountered") end
    if !(ex.args[1] in nonevaluation) return ex end
    filter(x->!isa(x,Number), vcat(map(getterms, ex.args[2:end])...))
end
evt(a) = Any[a]

function Terms(f::Formula)
    rhs = condense(distribute(dospecials(f.rhs)))
    tt = unique(getterms(rhs))
    tt = tt[!(tt .== 1)]             # drop any explicit 1's
    noint = (tt .== 0) | (tt .== -1) # should also handle :(-(expr,1))
    tt = tt[!noint]
    oo = Int[ord(t) for t in tt]     # orders of interaction terms
    if !issorted(oo)                 # sort terms by increasing order
        pp = sortperm(oo)
        tt = tt[pp]
        oo = oo[pp]
    end
    etrms = map(evt, tt)
    haslhs = f.lhs != nothing
    if haslhs
        unshift!(etrms, Any[f.lhs])
        unshift!(oo, 1)
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
    Formula(lhs,rhs)
end
