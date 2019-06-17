##Temporal Terms (Lag/Lead)

When working with time series data it is common to want to access past or future values of your predictors.
These are called lagged (past) or lead (future) variables.

### Basic Lead/Lag
```jldoctest
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

julia> f = @formula(y~ x + lag(x,2) + lead(x,2))
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

julia> modelcols(f, df)
([1.0, 2.0, 3.0, 4.0, 5.0], Union{Missing, Float64}[2.0 missing 6.0; 4.0 missing 8.0; … ; 8.0 4.0 missing; 10.0 6.0 missing])

julia> DataFrame(hcat(modelcols(f,df)...), Symbol.(vcat(coefnames(f)...)))
5×4 DataFrame
│ Row │ y        │ x        │ x_lag2   │ x_lead2  │
│     │ Float64⍰ │ Float64⍰ │ Float64⍰ │ Float64⍰ │
├─────┼──────────┼──────────┼──────────┼──────────┤
│ 1   │ 1.0      │ 2.0      │ missing  │ 6.0      │
│ 2   │ 2.0      │ 4.0      │ missing  │ 8.0      │
│ 3   │ 3.0      │ 6.0      │ 2.0      │ 10.0     │
│ 4   │ 4.0      │ 8.0      │ 4.0      │ missing  │
│ 5   │ 5.0      │ 10.0     │ 6.0      │ missing  │
```

StatsModels supports basic lead and lag functionality; as demonstrated above.
`lag(x, n)` accessed data for variable `x` from `n` rows (timesteps) ago.
`lead(x, n)` accessed data for variable `x` from `n` rows (timesteps) ahead.
In both cases, `n` can be ommitted, and it defaults to `1` row.
`missing` is used for any enties that are lagged or lead out of the table.

Note that this is a purely structural lead/lag term.
It is unaware of any time-index of the data.
It is up to the user to ensure the data is sorted, and following a regular time interval.
This may require insterting additional rows containing `missing`s  to fill in gaps in irregular data.
