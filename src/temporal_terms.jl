# Basic Lead/Lag:

# syntax:
lead_lag_docstring(op, opped, prevnext, firstlast) = """\n
        $op(term, nsteps::Integer)

    This `@formula` term is used to introduce $opped variables.
    For example `$op(x,1)` effectively adds a new column containing
    the value of the `x` column from the $prevnext row.
    If there is no such row (e.g. because this is the $firstlast row),
    then the $opped column will contain `missing` for that entry.

    Note: this is only a basic row-wise $op operation.
    It is up to the user to ensure that data is sorted by the temporal variable,
    and that observations are spaced with regular time-steps.
    (Which may require adding extra-rows filled with `missing` values.)
"""

@doc lead_lag_docstring("lag", "lagged", "previous", "first") lag
@doc lead_lag_docstring("lead", "lead", "next", "last") lead


# struct for behavior
struct LeadLagTerm{T<:AbstractTerm, F<:Union{typeof(lead), typeof(lag)}} <: AbstractTerm
    term::T
    nsteps::Int
end

function apply_schema(t::FunctionTerm{F}, sch::Schema, ctx::Type) where F<:Union{typeof(lead), typeof(lag)}
    opname = string(nameof(F.instance))
    if length(t.args_parsed) == 1  # lag(term)
        term_parsed = first(t.args_parsed)
        nsteps = 1
    elseif length(t.args_parsed) == 2  # lag(term, nsteps)
        term_parsed, nsteps_parsed = t.args_parsed
        (nsteps_parsed isa ConstantTerm) ||
            throw(ArgumentError("$opname step must be a number (got $nsteps_parsed)"))
        nsteps = nsteps_parsed.n
    else
        throw(ArgumentError("`$opname` terms require 1 or 2 arguments."))
    end

    term = apply_schema(term_parsed, sch, ctx)
    return LeadLagTerm{typeof(term), F}(term, nsteps)
end

function modelcols(ll::LeadLagTerm{<:Any, F}, d::Tables.ColumnTable) where F
    original_cols = modelcols(ll.term, d)
    return F.instance(original_cols, ll.nsteps)
end

width(ll::LeadLagTerm) = width(ll.term)
function Base.show(io::IO, ll::LeadLagTerm{<:Any, F}) where F
    opname = string(nameof(F.instance))
    print(io, "$opname($(ll.term), $(ll.nsteps))")
end
StatsBase.coefnames(ll::LeadLagTerm{<:Any, F}) where F = _llcoef(ll, coefnames(ll.term), string(nameof(F.instance)))
_llcoef(ll::LeadLagTerm, t::Symbol, opname) = Symbol(t, "_$opname$(ll.nsteps)")
_llcoef(ll::LeadLagTerm, ts, opname) = [Symbol(t, "_$opname$(ll.nsteps)") for t in ts]
