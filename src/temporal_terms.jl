# Basic Lag:

# syntax:
"""
    lag(term, nsteps::Integer)

This `@formula` term is used to introduce lagged variables.
For example `lag(x,1)` effectively adds a new column containing
the value of the `x` column from the previous row.
If there is no such row (e.g. because this is the first row), then the lagged column will
contain `missing`.

Note: this is only a basic row-wise lag operation.
It is up to the user to ensure that data is sorted by the temporal variable,
and that observations are spaced with regular time-steps.
(Which may require adding extra-rows filled with `missing` values.)
"""
lag(term, nsteps) = error("`lag`  should only be used within a @formula");

# type of model where syntax applies:
const LAG_CONTEXT = Any

# struct for behavior
struct LagTerm{T<:AbstractTerm} <: AbstractTerm
    term::T
    nsteps::Int
end

Base.show(io::IO, lag::LagTerm) = print(io, "lag($(lag.term), $(lag.nsteps))")

function apply_schema(t::FunctionTerm{typeof(lag)}, sch, mod::Type{<:LAG_CONTEXT})
    @assert length(t.args_parsed) == 2
    term_parsed, nsteps_parsed = t.args_parsed

    term = apply_schema(term_parsed, sch, mod)

    (nsteps_parsed isa ConstantTerm) ||
        throw(ArgumentError("Lag step must be a number (got $step_parsed)"))

    nsteps = nsteps_parsed.n
    return LagTerm(term, nsteps)
end

function modelcols(lag::LagTerm, d::NamedTuple)
    original_cols = modelcols(lag.term, d)
    n_cols = size(original_cols, 2)
    padding = fill(missing, (lag.nsteps, n_cols))
    padded_cols = [padding; original_cols]
    return padded_cols[1:size(original_cols, 1), :]
end

width(lag::LagTerm) = width(lag.term)

function StatsBase.coefnames(lag::LagTerm)
    return coefnames(lag.term) .* "_lagged_by_$(lag.nsteps)"
end
