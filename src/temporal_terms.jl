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

terms(t::LeadLagTerm) = (t.term, )

function apply_schema(t::FunctionTerm{F}, sch::Schema, ctx::Type) where F<:Union{typeof(lead), typeof(lag)}
    opname = string(nameof(F.instance))
    if length(t.args) == 1  # lag(term)
        term = first(t.args)
        nsteps = 1
    elseif length(t.args) == 2  # lag(term, nsteps)
        term, nsteps = t.args
        (nsteps isa ConstantTerm) ||
            throw(ArgumentError("$opname step must be a number (got $nsteps)"))
        nsteps = nsteps.n
    else
        throw(ArgumentError("`$opname` terms require 1 or 2 arguments."))
    end

    term = apply_schema(term, sch, ctx)
    return LeadLagTerm{typeof(term), F}(term, nsteps)
end

function apply_schema(t::LeadLagTerm{T, F}, sch::Schema, ctx::Type) where {T,F}
    term = apply_schema(t.term, sch, ctx)
    LeadLagTerm{typeof(term), F}(term, t.nsteps)
end

ShiftedArrays.lead(t::T, n=1) where {T<:AbstractTerm} = LeadLagTerm{T,typeof(lead)}(t, n)
ShiftedArrays.lag(t::T, n=1) where {T<:AbstractTerm} = LeadLagTerm{T,typeof(lag)}(t, n)

function modelcols(ll::LeadLagTerm{<:Any, F}, d::Tables.ColumnTable) where F
    original_cols = modelcols(ll.term, d)
    return F.instance(original_cols, ll.nsteps)
end

width(ll::LeadLagTerm) = width(ll.term)
function Base.show(io::IO, ll::LeadLagTerm{<:Any, F}) where F
    opname = string(nameof(F.instance))
    print(io, "$opname($(ll.term), $(ll.nsteps))")
end
function StatsAPI.coefnames(ll::LeadLagTerm{<:Any, F}) where F
    opname = string(nameof(F.instance))
    coefnames(ll.term) .* "_$opname$(ll.nsteps)"
end
