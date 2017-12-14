module TestStatsModels

using StatsModels
using StatsBase
using DataFrames
using Compat
using Compat.Test

# Tests for statsmodel.jl

# A dummy RegressionModel type
struct DummyMod <: RegressionModel
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
d[:x1] = Vector{Union{Missing, Int}}(5:8)
d[:x2] = [9:12;]
d[:x3] = [13:16;]
d[:x4] = [17:20;]

f = @formula(y ~ x1 * x2)
m = fit(DummyMod, f, d)
@test model_response(m) == Array(d[:y])

## test prediction method
## vanilla
StatsBase.predict(mod::DummyMod) = mod.x * mod.beta
@test predict(m) == [ ones(size(d,1)) Array(d[:x1]) Array(d[:x2]) Array(d[:x1]).*Array(d[:x2]) ] * collect(1:4)

## new data from matrix
StatsBase.predict(mod::DummyMod, newX::Matrix) = newX * mod.beta
mm = ModelMatrix(ModelFrame(f, d))
@test predict(m, mm.m) == mm.m * collect(1:4)

## new data from DataFrame (via ModelMatrix)
@test predict(m, d) == predict(m, mm.m)

d2 = deepcopy(d)
d2[3, :x1] = missing
@test length(predict(m, d2)) == 4

## test copying of names from Terms to CoefTable
ct = coeftable(m)
@test ct.rownms == ["(Intercept)", "x1", "x2", "x1 & x2"]

## show with coeftable defined
io = IOBuffer()
show(io, m)

## with categorical variables
d[:x1p] = CategoricalArray{Union{Missing, Int}}(d[:x1])
f2 = @formula(y ~ x1p)
m2 = fit(DummyMod, f2, d)

@test coeftable(m2).rownms == ["(Intercept)", "x1p: 6", "x1p: 7", "x1p: 8"]

## predict w/ new data missing levels
@test predict(m2, d[2:4, :]) == predict(m2)[2:4]

## predict w/ new data with _extra_ levels (throws an error)
d3 = deepcopy(d)
d3[1, :x1] = 0
d3[:x1p] = CategoricalVector{Union{Missing, Int}}(d3[:x1])
@test_throws ArgumentError predict(m2, d3)

## fit with contrasts specified
d[:x2p] = CategoricalVector{Union{Missing, Int}}(d[:x2])
f3 = @formula(y ~ x1p + x2p)
m3 = fit(DummyMod, f3, d)
fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding()))
fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding(),
                                      :x2p => DummyCoding()))
@test_throws Exception fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding(),
                                                             :x2p => 1))

# A dummy RegressionModel type that does not support intercept
struct DummyModNoIntercept <: RegressionModel
    beta::Vector{Float64}
    x::Matrix
    y::Vector
end

StatsModels.drop_intercept(::Type{DummyModNoIntercept}) = true

## dumb fit method: just copy the x and y input over
StatsBase.fit(::Type{DummyModNoIntercept}, x::Matrix, y::Vector) =
    DummyModNoIntercept(collect(1:size(x, 2)), x, y)
StatsBase.model_response(mod::DummyModNoIntercept) = mod.y
## dumb coeftable: just prints the "beta" values
StatsBase.coeftable(mod::DummyModNoIntercept) =
    CoefTable(reshape(mod.beta, (size(mod.beta,1), 1)),
             ["'beta' value"],
             ["" for n in 1:size(mod.x,2)],
             0)

f1 = @formula(y ~ 1 + x1 * x2)
f2 = @formula(y ~ 0 + x1 * x2)
m1 = fit(DummyModNoIntercept, f1, d)
m2 = fit(DummyModNoIntercept, f2, d)
ct1 = coeftable(m1)
ct2 = coeftable(m2)
@test ct1.rownms == ct2.rownms == ["x1", "x2", "x1 & x2"]

f1 = @formula(y ~ 1 + x1p)
f2 = @formula(y ~ 0 + x1p)
m1 = fit(DummyModNoIntercept, f1, d)
m2 = fit(DummyModNoIntercept, f2, d)
ct1 = coeftable(m1)
ct2 = coeftable(m2)
@test ct1.rownms == ct2.rownms == ["x1p: 6", "x1p: 7", "x1p: 8"]

## Another dummy model type to test fall-through show method
struct DummyModTwo <: RegressionModel
    msg::String
end

StatsBase.fit(::Type{DummyModTwo}, ::Matrix, ::Vector) = DummyModTwo("hello!")
Base.show(io::IO, m::DummyModTwo) = println(io, m.msg)

m2 = fit(DummyModTwo, f, d)
show(io, m2)

end
