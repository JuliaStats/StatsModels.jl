# these need to be at the top level:

# A dummy RegressionModel type
struct DummyMod <: RegressionModel
    beta::Vector{Float64}
    x::Matrix
    y::Vector
end

## dumb fit method: just copy the x and y input over
StatsAPI.fit(::Type{DummyMod}, x::Matrix, y::Vector) =
    DummyMod(collect(1:size(x, 2)), x, y)
StatsAPI.response(mod::DummyMod) = mod.y
## dumb coeftable: just prints the "beta" values
StatsAPI.coeftable(mod::DummyMod) =
    CoefTable(reshape(mod.beta, (size(mod.beta,1), 1)),
              ["'beta' value"],
              ["" for n in 1:size(mod.x,2)],
              0)
# dumb predict: return values predicted by "beta" and dummy confidence bounds
function StatsAPI.predict(mod::DummyMod;
                          interval::Union{Nothing,Symbol}=nothing)
    pred = mod.x * mod.beta
    if interval === nothing
        return pred
    elseif interval === :prediction
        return (prediction=pred, lower=pred .- 1, upper=pred .+ 1)
    else
        throw(ArgumentError("value not allowed for interval"))
    end
end
function StatsAPI.predict(mod::DummyMod, newX::Matrix;
                          interval::Union{Nothing,Symbol}=nothing)
    pred = newX * mod.beta
    if interval === nothing
        return pred
    elseif interval === :prediction
        return (prediction=pred, lower=pred .- 1, upper=pred .+ 1)
    else
        throw(ArgumentError("value not allowed for interval"))
    end
end
StatsAPI.dof(mod::DummyMod) = length(mod.beta)
StatsAPI.dof_residual(mod::DummyMod) = length(mod.y) - length(mod.beta)
StatsAPI.nobs(mod::DummyMod) = length(mod.y)
StatsAPI.deviance(mod::DummyMod) = sum((response(mod) .- predict(mod)).^2)
# Incorrect but simple definition
StatsModels.isnested(mod1::DummyMod, mod2::DummyMod; atol::Real=0.0) =
    dof(mod1) <= dof(mod2)
StatsAPI.loglikelihood(mod::DummyMod) = -sum((response(mod) .- predict(mod)).^2)
StatsAPI.loglikelihood(mod::DummyMod, ::Colon) = -(response(mod) .- predict(mod)).^2

# A dummy RegressionModel type that does not support intercept
struct DummyModNoIntercept <: RegressionModel
    beta::Vector{Float64}
    x::Matrix
    y::Vector
end

StatsModels.drop_intercept(::Type{DummyModNoIntercept}) = true

## dumb fit method: just copy the x and y input over
StatsAPI.fit(::Type{DummyModNoIntercept}, x::Matrix, y::Vector) =
    DummyModNoIntercept(collect(1:size(x, 2)), x, y)
StatsAPI.response(mod::DummyModNoIntercept) = mod.y
## dumb coeftable: just prints the "beta" values
StatsAPI.coeftable(mod::DummyModNoIntercept) =
    CoefTable(reshape(mod.beta, (size(mod.beta,1), 1)),
              ["'beta' value"],
              ["" for n in 1:size(mod.x,2)],
              0)
# dumb predict: return values predicted by "beta" and dummy confidence bounds
function StatsAPI.predict(mod::DummyModNoIntercept;
                           interval::Union{Nothing,Symbol}=nothing)
    pred = mod.x * mod.beta
    if interval === nothing
        return pred
    elseif interval === :prediction
        return (prediction=pred, lower=pred .- 1, upper=pred .+ 1)
    else
        throw(ArgumentError("value not allowed for interval"))
    end
end
function StatsAPI.predict(mod::DummyModNoIntercept, newX::Matrix;
                           interval::Union{Nothing,Symbol}=nothing)
    pred = newX * mod.beta
    if interval === nothing
        return pred
    elseif interval === :prediction
        return (prediction=pred, lower=pred .- 1, upper=pred .+ 1)
    else
        throw(ArgumentError("value not allowed for interval"))
    end
end
StatsAPI.dof(mod::DummyModNoIntercept) = length(mod.beta)
StatsAPI.dof_residual(mod::DummyModNoIntercept) = length(mod.y) - length(mod.beta)
StatsAPI.nobs(mod::DummyModNoIntercept) = length(mod.y)
StatsAPI.deviance(mod::DummyModNoIntercept) = sum((response(mod) .- predict(mod)).^2)
# isnested not implemented to test fallback
StatsAPI.loglikelihood(mod::DummyModNoIntercept) = -sum((response(mod) .- predict(mod)).^2)
StatsAPI.loglikelihood(mod::DummyModNoIntercept, ::Colon) = -(response(mod) .- predict(mod)).^2

## Another dummy model type to test fall-through show method
struct DummyModTwo <: RegressionModel
    msg::String
end

StatsAPI.fit(::Type{DummyModTwo}, ::Matrix, ::Vector) = DummyModTwo("hello!")
Base.show(io::IO, m::DummyModTwo) = println(io, m.msg)

@testset "stat model types" begin

    ## Test fitting
    d = DataFrame(y = 1:4,
                  x1 = allowmissing(5:8),
                  x2 = 9:12,
                  x3 = 13:16,
                  x4 = 17:20)

    d.x1p = categorical(d.x1)

    f = @formula(y ~ x1 * x2)
    m = fit(DummyMod, f, d)
    @test response(m) == Array(d.y)

    ## coefnames delegated to model frame by default
    @test coefnames(m) == coefnames(ModelFrame(f, d)) == ["(Intercept)", "x1", "x2", "x1 & x2"]

    @test formula(m) == m.mf.f

    ## loglikelihood methods from StatsBase
    @test length(loglikelihood(m, :)) == nrow(d)
    @test sum(loglikelihood(m, :)) == loglikelihood(m) == -deviance(m)

    ## test prediction method
    ## vanilla
    @test predict(m) == [ ones(size(d,1)) Array(d.x1) Array(d.x2) Array(d.x1).*Array(d.x2) ] * collect(1:4)

    ## new data from matrix
    mm = ModelMatrix(ModelFrame(f, d))
    p = predict(m, mm.m)
    @test p == mm.m * collect(1:4)
    p2 = predict(m, mm.m, interval=:prediction)
    @test p2 isa NamedTuple
    @test p2.prediction == p
    @test p2.lower == p .- 1
    @test p2.upper == p .+ 1

    ## new data from DataFrame (via ModelMatrix)
    @test predict(m, d) == p
    p3 = predict(m, d, interval=:prediction)
    @test p3 isa DataFrame
    @test p3.prediction == p
    @test p3.lower == p .- 1
    @test p3.upper == p .+ 1

    d2 = deepcopy(d)
    d2[3, :x1] = missing
    @test length(predict(m, d2)) == 4

    ## test copying of names from Terms to CoefTable
    ct = coeftable(m)
    @test ct.rownms == ["(Intercept)", "x1", "x2", "x1 & x2"]
    @test termnames(m) == ("y", ["(Intercept)", "x1", "x2", "x1 & x2"])

    ## show with coeftable defined
    io = IOBuffer()
    show(io, m)

    ## with categorical variables
    f2 = @formula(y ~ x1p)
    m2 = fit(DummyMod, f2, d)

    @test coeftable(m2).rownms == ["(Intercept)", "x1p: 6", "x1p: 7", "x1p: 8"]
    @test termnames(m2) == ("y", ["(Intercept)", "x1p"])

    ## predict w/ new data missing levels
    @test predict(m2, d[2:4, :]) == predict(m2)[2:4]

    ## predict w/ new data with _extra_ levels (throws an error)
    d3 = deepcopy(d)
    d3[1, :x1] = 0
    d3.x1p = categorical(d3.x1)
    # TODO: check for level mismatch earlier...this throws a KeyError when it
    # goes to do the lookup in the contrasts matrix from the previously
    # generated categorical term.
    @test_throws KeyError predict(m2, d3)
    # @test_throws ArgumentError predict(m2, d3)

    ## predict with dataframe that doesn't have the dependent variable
    d4 = deepcopy(d)
    select!(d4, Not(:y))
    @test predict(m, d4) == predict(m, d)

    ## attempting to fit with d4 should fail since it doesn't have :y
    @test_throws ArgumentError fit(DummyMod, f, d4)

    ## fit with contrasts specified
    d.x2p = categorical(d.x2)
    f3 = @formula(y ~ x1p + x2p)
    m3 = fit(DummyMod, f3, d)
    fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding()))
    fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding(),
                                          :x2p => DummyCoding()))
    @test_throws Exception fit(DummyMod, f3, d, contrasts = Dict(:x1p => EffectsCoding(),
                                                                 :x2p => 1))


    f1 = @formula(y ~ 1 + x1 * x2)
    f2 = @formula(y ~ 0 + x1 * x2)
    f3 = @formula(y ~ x1 * x2)
    @test_throws ArgumentError m1 = fit(DummyModNoIntercept, f1, d)
    m2 = fit(DummyModNoIntercept, f2, d)
    m3 = fit(DummyModNoIntercept, f3, d)
    ct2 = coeftable(m2)
    ct3 = coeftable(m3)
    @test ct3.rownms == ct2.rownms == ["x1", "x2", "x1 & x2"]
    @test predict(m2, d[2:4, :]) == predict(m2)[2:4]
    @test predict(m3, d[2:4, :]) == predict(m3)[2:4]

    f1 = @formula(y ~ 1 + x1p)
    f2 = @formula(y ~ 0 + x1p)
    f3 = @formula(y ~ x1p)
    @test_throws ArgumentError m1 = fit(DummyModNoIntercept, f1, d)
    m2 = fit(DummyModNoIntercept, f2, d)
    m3 = fit(DummyModNoIntercept, f3, d)
    ct2 = coeftable(m2)
    ct3 = coeftable(m3)
    @test ct2.rownms == ct3.rownms == ["x1p: 6", "x1p: 7", "x1p: 8"]
    m4 = fit(DummyModNoIntercept, f3, d, contrasts = Dict(:x1p => EffectsCoding()))
    @test predict(m2, d[2:4, :]) == predict(m2)[2:4]
    @test predict(m3, d[2:4, :]) == predict(m3)[2:4]
    @test predict(m4, d[2:4, :]) == predict(m4)[2:4]

    m2 = fit(DummyModTwo, f, d)
    # make sure show() still works when there is no coeftable method
    show(io, m2)
end

@testset "termnames" begin
    # one final termnames check
    # note that `1` is still a ConstantTerm and not yet InterceptTerm
    # because apply_schema hasn't been called
    @test termnames(@formula(y ~ 1 + log(x) * y + (1+x|g)))[2] ==
          ["1", "log(x)", "y", "log(x) & y", "(1 + x) | g"]
    @test termnames(ConstantTerm(1)) == "1"
    @test termnames(Term(:x)) == "x"
    @test termnames(InterceptTerm{true}()) == "(Intercept)"
    @test termnames(InterceptTerm{false}()) == String[]
    @test termnames(ContinuousTerm(:x, 1, 0, 0, 0)) == "x"
    cm = StatsModels.ContrastsMatrix([1 0; 0 1], ["b", "c"], ["a", "b", "c"], DummyCoding())
    @test termnames(CategoricalTerm(:x, cm)) == "x"
    @test termnames(FunctionTerm(log, [Term(:x)], :(log(x)))) == "log(x)"
    @test termnames(InteractionTerm(term.((:a, :b, :c)))) == "a & b & c"
    @test termnames(MatrixTerm(term(:a))) == ["a"]
    @test termnames(MatrixTerm((term(:a), term(:b)))) == ["a", "b"]
    @test termnames((term(:a), term(:b))) == ["a", "b"]
    @test termnames((term(:a),)) == ["a"]
end

@testset "lrtest" begin

    y = collect(1:4)
    x1 = 2:5
    x2 = [1, 5, 3, 1]

    m0 = DummyMod([1], ones(4, 1), y)
    m1 = DummyMod([1, 0.3], [ones(4, 1) x1], y)
    m2 = DummyMod([1, 0.25, 0.05, 0.04], [ones(4, 1) x1 x2 x1.*x2], y)

    @test_throws ArgumentError lrtest(m0)
    @test_throws ArgumentError lrtest(m0, m0)
    @test_throws ArgumentError lrtest(m0, m2, m1)
    @test_throws ArgumentError lrtest(m1, m0, m2)
    @test_throws ArgumentError lrtest(m2, m0, m1)

    m1b = DummyMod([1, 0.3], [ones(3, 1) x1[2:end]], y[2:end])
    @test_throws ArgumentError lrtest(m0, m1b)

    lr1 = lrtest(m0, m1)
    @test isnan(lr1.pval[1])
    @test lr1.pval[2] ≈ 3.57538284869704e-6
    @test sprint(show, lr1) == """
        Likelihood-ratio test: 2 models fitted on 4 observations
        ──────────────────────────────────────────────────────
             DOF  ΔDOF    LogLik  Deviance    Chisq  p(>Chisq)
        ──────────────────────────────────────────────────────
        [1]    1        -14.0000   14.0000                    
        [2]    2     1   -3.2600    3.2600  21.4800     <1e-05
        ──────────────────────────────────────────────────────"""

    @testset "isnested with TableRegressionModel" begin
        d = DataFrame(y=y, x1=x1, x2=x2)

        m0 = fit(DummyMod, @formula(y ~ 1), d)
        m1 = fit(DummyMod, @formula(y ~ 1 + x1), d)
        m2 = fit(DummyMod, @formula(y ~ 1 + x1 * x2), d)

        @test StatsModels.isnested(m0, m1)
        @test StatsModels.isnested(m1, m2)
        @test StatsModels.isnested(m0, m2)
    end


    m0 = DummyModNoIntercept(Float64[], ones(4, 0), y)
    m1 = DummyModNoIntercept([0.3], reshape(x1, :, 1), y)
    m2 = DummyModNoIntercept([0.25, 0.05, 0.04], [x1 x2 x1.*x2], y)

    @test_throws ArgumentError lrtest(m0)
    @test_throws ArgumentError lrtest(m0, m0)
    @test_throws ArgumentError lrtest(m0, m2, m1)
    @test_throws ArgumentError lrtest(m1, m0, m2)
    @test_throws ArgumentError lrtest(m2, m0, m1)

    m1b = DummyModNoIntercept([0.3], reshape(x1[2:end], :, 1), y[2:end])
    @test_throws ArgumentError lrtest(m0, m1b)

    # Incorrect, but check that it doesn't throw an error
    lr2 = @test_logs((:warn, "Could not check whether models are nested " *
                     "as model type DummyModNoIntercept does not implement isnested: " *
                     "results may not be meaningful"),
                     lrtest(m0, m1))
    @test isnan(lr2.pval[1])
    @test lr2.pval[2] ≈ 6.128757581368316e-10

    # in 1.6, p value printing has changed (JuliaStats/StatsBase.jl#606)
    if VERSION > v"1.6.0-DEV"
        @test sprint(show, lr2) == """
            Likelihood-ratio test: 2 models fitted on 4 observations
            ──────────────────────────────────────────────────────
                 DOF  ΔDOF    LogLik  Deviance    Chisq  p(>Chisq)
            ──────────────────────────────────────────────────────
            [1]    0        -30.0000   30.0000                    
            [2]    1     1  -10.8600   10.8600  38.2800     <1e-09
            ──────────────────────────────────────────────────────"""
    else
        @test sprint(show, lr2) == """
            Likelihood-ratio test: 2 models fitted on 4 observations
            ──────────────────────────────────────────────────────
                 DOF  ΔDOF    LogLik  Deviance    Chisq  p(>Chisq)
            ──────────────────────────────────────────────────────
            [1]    0        -30.0000   30.0000                    
            [2]    1     1  -10.8600   10.8600  38.2800      <1e-9
            ──────────────────────────────────────────────────────"""
    end

    # Test that model with more degrees of freedom that does not improve
    # fit compared with simpler model is accepted, even if likelihood is
    # lower with some tolerance
    lrtest(DummyMod([1], ones(4, 1), y), DummyMod([1, 0], ones(4, 2), y))
    lrtest(DummyMod([1], ones(4, 1), y), DummyMod([1, -1e-8], ones(4, 2), y))
    lrtest(DummyMod([1], ones(4, 1), y), DummyMod([1, -1e-2], ones(4, 2), y), atol=1)
    @test_throws ArgumentError lrtest(DummyMod([1], ones(4, 1), y),
                                      DummyMod([1, -1e-2], ones(4, 2), y))

end
