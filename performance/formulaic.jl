using StatsModels, DataFrames, RCall, Tables
using BenchmarkTools

df = rcopy(R"""
library(Matrix)
library(glue)
s <- 1000000
df <- data.frame(
    "A"=rep(c('a', 'b', 'c'), s),
    "B"=rep(c('d', 'e', 'f'), s),
    "C"=rep(c('g', 'h', 'i'), s),
    "D"=rep(c('j', 'k', 'l'), s),
    "a"=rnorm(3*s),
    "b"=rnorm(3*s),
    "c"=rnorm(3*s),
    "d"=rnorm(3*s)
)
""")


formulas = [
    @formula(0 ~ a),
    @formula(0 ~ A),
    @formula(0 ~ a+A),
    @formula(0 ~ a&A),
    @formula(0 ~ A+B),
    @formula(0 ~ a&A&B),
    @formula(0 ~ A&B&C&D),
    @formula(0 ~ a*b*A*B),
    @formula(0 ~ a*b*c*A*B*C)
]

sch = schema(df)
dt = Tables.columntable(df)

timings = map(formulas) do f
    ff = apply_schema(f, sch, StatisticalModel)
    println(f)
    @benchmark modelcols($(ff.rhs), $dt)
end
