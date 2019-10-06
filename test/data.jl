using StatsModels, StatsBase

using StatsModels: apply_data, ModelCols

f = @formula(y ~ 1 + a*b)

d = (y = rand(20),
     a = rand(20),
     b = sample('a':'d', 5))

ff = apply_schema(f, schema(d))

fff = apply_data(ff, d)

b = fff.term.rhs[end-1]

b[:, :]
