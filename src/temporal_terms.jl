# Basic Lead/Lag:

# syntax:
lead_lag_docstring(op, opped, prevnext, firstlast) = """
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

"""
    $(lead_lag_docstring("lag", "lagged", "previous", "first"))"
"""
function lag end

"""
    $(lead_lag_docstring("lead", "lead", "next", "last"))"
"""
function lag end


# struct for behavior
struct LeadLagTerm{T<:AbstractTerm, F<:Union{typeof(lead), typeof(lag)}} <: AbstractTerm
    term::T
    nsteps::Int
end

op(::LeadLagTerm{<:Any, typeof(lag)}) = lag
op(::LeadLagTerm{<:Any, typeof(lead)}) = lead
opname(::LeadLagTerm{<:Any, typeof(lag)}) = "lag"
opname(::LeadLagTerm{<:Any, typeof(lead)}) = "lead"


function apply_schema(t::FunctionTerm{F}, sch, ctx::Type) where F<:Union{typeof(lead), typeof(lag)}
    opname = string(F.instance)
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

function modelcols(ll::LeadLagTerm, d::Tables.ColumnTable)
    original_cols = modelcols(ll.term, d)
    return op(ll)(original_cols, ll.nsteps)
end

width(ll::LeadLagTerm) = width(ll.term)
Base.show(io::IO, ll::LeadLagTerm) = print(io, "$(opname(ll))($(ll.term), $(ll.nsteps))")
StatsBase.coefnames(ll::LeadLagTerm) = coefnames(ll.term) .* "_$(opname(ll))$(ll.nsteps)"
