module TestStatsModels
using DataFrames
using Base.Test

# Tests for statsmodel.jl

# A dummy RegressionModel type
immutable DummyMod <: RegressionModel
    beta::Vector{Float64}
    x::Matrix
    y::Vector
end

## dumb fit method: just copy the x and y input over
StatsBase.fit(::Type{DummyMod}, x::Matrix, y::Vector) =
    DummyMod(collect(1:size(x, 2)), x, y)
StatsBase.model_response(mod::DummyMod) = mod.y
## dumb coeftable: just prints the "beta" values
StatsBase.coeftable(mod::DummyMod) =
    CoefTable(reshape(mod.beta, (size(mod.beta,1), 1)),
              ["'beta' value"],
              ["" for n in 1:size(mod.x,2)],
              0)

## Test fitting
d = DataFrame()
d[:y] = [1:4;]
d[:x1] = [5:8;]
d[:x2] = [9:12;]
d[:x3] = [13:16;]
d[:x4] = [17:20;]

f = y ~ x1 * x2
m = fit(DummyMod, f, d)
@test model_response(m) == d[:y]

## test prediction method
## vanilla
StatsBase.predict(mod::DummyMod) = mod.x * mod.beta
@test predict(m) == [ ones(size(d,1)) d[:x1] d[:x2] d[:x1].*d[:x2] ] * collect(1:4)

## new data from matrix
StatsBase.predict(mod::DummyMod, newX::Matrix) = newX * mod.beta
mm = ModelMatrix(ModelFrame(f, d))
@test predict(m, mm.m) == mm.m * collect(1:4)

## new data from DataFrame (via ModelMatrix)
@test predict(m, d) == predict(m, mm.m)

d2 = deepcopy(d)
d2[3, :x1] = NA
@test length(predict(m, d2)) == 4

## test copying of names from Terms to CoefTable
ct = coeftable(m)
@test ct.rownms == ["(Intercept)", "x1", "x2", "x1 & x2"]

## show with coeftable defined
@show m

## with categorical variables
d[:x1p] = PooledDataArray(d[:x1])
f2 = y ~ x1p
m2 = fit(DummyMod, f2, d)

@test coeftable(m2).rownms == ["(Intercept)", "x1p - 6", "x1p - 7", "x1p - 8"]

## predict w/ new data missing levels
## FAILS: mismatch between number of model matrix columns
## @test predict(m2, d[2:4, :]) == predict(m2)[2:4]


## Another dummy model type to test fall-through show method
immutable DummyModTwo <: RegressionModel
    msg::String
end

StatsBase.fit(::Type{DummyModTwo}, ::Matrix, ::Vector) = DummyModTwo("hello!")
Base.show(io::IO, m::DummyModTwo) = println(io, m.msg)

m2 = fit(DummyModTwo, f, d)
@show m2

end
