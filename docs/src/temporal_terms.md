## Temporal Terms (Lag/Lead)

When working with time series data it is common to want to access past or future values of your predictors.
These are called lagged (past) or lead (future) variables.

StatsModels supports basic lead and lag functionality:

- `lag(x, n)` accesses data for variable `x` from `n` rows (time steps) ago.
- `lead(x, n)` accesses data for variable `x` from `n` rows (time steps) ahead.

In both cases, `n` can be omitted, and it defaults to `1` row.
`missing` is used for any entries that are lagged or lead out of the table.

Note that this is a purely structural lead/lag term: it is unaware of any
time index of the data. It is up to the user to ensure the data is sorted,
and following a regular time interval, which may require inserting additional
rows containing `missing`s  to fill in gaps in irregular data.

Below is a simple example:
```jldoctest leadlag
julia> using StatsModels, DataFrames

julia> df = DataFrame(y=1:5, x=2:2:10)
5×2 DataFrame
│ Row │ y     │ x     │
│     │ Int64 │ Int64 │
├─────┼───────┼───────┤
│ 1   │ 1     │ 2     │
│ 2   │ 2     │ 4     │
│ 3   │ 3     │ 6     │
│ 4   │ 4     │ 8     │
│ 5   │ 5     │ 10    │

julia> f = @formula(y ~ x + lag(x, 2) + lead(x, 2))
FormulaTerm
Response:
  y(unknown)
Predictors:
  x(unknown)
  (x)->lag(x, 2)
  (x)->lead(x, 2)

julia> f = apply_schema(f, schema(f, df))
FormulaTerm
Response:
  y(continuous)
Predictors:
  x(continuous)
  lag(x, 2)
  lead(x, 2)

julia> modelmatrix(f, df)
5×3 reshape(::Array{Union{Missing, Int64},2}, 5, 3) with eltype Union{Missing, Int64}:
  2   missing   6
  4   missing   8
  6  2         10
  8  4           missing
 10  6           missing
```

### Programmatic construction of lead and lag terms

StatsModels.jl provides methods for `lead` and `lag` that allow `LeadLagTerm`s
to be constructed programmatically (at run time).  See the section on
[Constructing a formula programmatically](@ref) for more information.  For a
short example, you can produce the same formula as above without the `@formula`
macro like this:

```jldoctest leadlag
julia> y, x = term(:y), term(:x);

julia> f2 = y ~ x + lag(x, 2) + lead(x, 2)
FormulaTerm
Response:
  y(unknown)
Predictors:
  x(unknown)
  lag(x, 2)
  lead(x, 2)

julia> f2 = apply_schema(f2, schema(f2, df))
FormulaTerm
Response:
  y(continuous)
Predictors:
  x(continuous)
  lag(x, 2)
  lead(x, 2)

julia> modelmatrix(f2, df)
5×3 reshape(::Array{Union{Missing, Int64},2}, 5, 3) with eltype Union{Missing, Int64}:
  2   missing   6       
  4   missing   8       
  6  2         10       
  8  4           missing
 10  6           missing
```
