struct LRTestResult{N}
    nobs::Int
    deviance::NTuple{N, Float64}
    dof::NTuple{N, Int}
    pval::NTuple{N, Float64}
end

_diff(t::NTuple{N}) where {N} = ntuple(i->t[i+1]-t[i], N-1)

"""
    isnested(m1::StatisticalModel, m2::StatisticalModel; atol::Real=0.0)

Indicate whether model `m1` is nested in model `m2`, i.e. whether
`m1` can be obtained by constraining some parameters in `m2`.
Both models must have been fitted on the same data.
"""
function isnested end

"""
    lrtest(mods::StatisticalModel...; atol::Real=0.0)

For each sequential pair of statistical models in `mods...`, perform a likelihood ratio
test to determine if the first one fits significantly better than the next.

A table is returned containing degrees of freedom (DOF),
difference in DOF from the preceding model, deviance, difference in deviance
from the preceding model, and likelihood ratio and p-value for the comparison
between the two models.

Optional keyword argument `atol` controls the numerical tolerance when testing whether
the models are nested.

# Examples

Suppose we want to compare the effects of two or more treatments on some result.
Our null hypothesis is that `Result ~ 1` fits the data as well as
`Result ~ 1 + Treatment`.

```jldoctest
julia> using DataFrames, GLM

julia> dat = DataFrame(Result=[1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1],
                       Treatment=[1, 1, 1, 2, 2, 2, 1, 1, 1, 2, 2, 2],
                       Other=categorical([1, 1, 2, 1, 2, 1, 3, 1, 1, 2, 2, 1]));

julia> nullmodel = glm(@formula(Result ~ 1), dat, Binomial(), LogitLink());

julia> model = glm(@formula(Result ~ 1 + Treatment), dat, Binomial(), LogitLink());

julia> bigmodel = glm(@formula(Result ~ 1 + Treatment + Other), dat, Binomial(), LogitLink());

julia> lrtest(nullmodel, model, bigmodel)
┌ Warning: Could not check whether models are nested as model type TableRegressionModel does not implement isnested: results may not be meaningful
└ @ StatsModels ~/.julia/dev/StatsModels/src/lrtest.jl:104
Likelihood-ratio test: 3 models fitted on 12 observations
──────────────────────────────────────────────
     DOF  ΔDOF  Deviance  ΔDeviance  p(>Chisq)
──────────────────────────────────────────────
[1]    1         16.3006
[2]    2     1   15.9559    -0.3447     0.5571
[3]    4     2   14.0571    -1.8988     0.3870
──────────────────────────────────────────────

julia> lrtest(bigmodel, model, nullmodel)
┌ Warning: Could not check whether models are nested as model type TableRegressionModel does not implement isnested: results may not be meaningful
└ @ StatsModels ~/.julia/dev/StatsModels/src/lrtest.jl:104
Likelihood-ratio test: 3 models fitted on 12 observations
──────────────────────────────────────────────
     DOF  ΔDOF  Deviance  ΔDeviance  p(>Chisq)
──────────────────────────────────────────────
[1]    4         14.0571
[2]    2    -2   15.9559     1.8988     0.3870
[3]    1    -1   16.3006     0.3447     0.5571
──────────────────────────────────────────────
```
"""
function lrtest(mods::StatisticalModel...; atol::Real=0.0)
    if length(mods) < 2
        throw(ArgumentError("At least two models are needed to perform LR test"))
    end
    T = typeof(mods[1])
    df = dof.(mods)
    forward = df[1] <= df[2]
    if !all(m -> typeof(m) == T, mods)
        throw(ArgumentError("LR test is only valid for models of the same type"))
    end
    if !all(==(nobs(mods[1])), nobs.(mods))
        throw(ArgumentError("LR test is only valid for models fitted on the same data, " *
                            "but number of observations differ"))
    end
    checknested = hasmethod(isnested, Tuple{T, T})
    if forward
        for i in 2:length(mods)
            if df[i-1] >= df[i] ||
                (checknested && !isnested(mods[i-1], mods[i], atol=atol))
                throw(ArgumentError("LR test is only valid for nested models"))
            end
        end
    else
        for i in 2:length(mods)
            if df[i] >= df[i-1] ||
                (checknested && !isnested(mods[i], mods[i-1], atol=atol))
                throw(ArgumentError("LR test is only valid for nested models"))
            end
        end
    end
    if !checknested
        @warn "Could not check whether models are nested as model type " *
            "$(nameof(T)) does not implement isnested: results may not be meaningful"
    end

    dev = deviance.(mods)
    Δdev = _diff(dev)

    Δdf = _diff(df)
    dfr = Int.(dof_residual.(mods))

    if (forward && any(x -> x > 0, Δdev)) || (!forward && any(x -> x < 0, Δdev))
        throw(ArgumentError("Residual deviance must be strictly lower " *
                            "in models with more degrees of freedom"))
    end

    pval = (NaN, chisqccdf.(abs.(Δdf), abs.(Δdev))...)
    return LRTestResult(Int(nobs(mods[1])), dev, df, pval)
end

function Base.show(io::IO, lrr::LRTestResult{N}) where N
    Δdf = _diff(lrr.dof)
    Δdev = _diff(lrr.deviance)

    nc = 6
    nr = N
    outrows = Matrix{String}(undef, nr+1, nc)

    outrows[1, :] = ["", "DOF", "ΔDOF", "Deviance", "ΔDeviance", "p(>Chisq)"]

    outrows[2, :] = ["[1]", @sprintf("%.0d", lrr.dof[1]), " ",
                     @sprintf("%.4f", lrr.deviance[1]), " ", " "]

    for i in 2:nr
        outrows[i+1, :] = ["[$i]", @sprintf("%.0d", lrr.dof[i]),
                           @sprintf("%.0d", Δdf[i-1]),
                           @sprintf("%.4f", lrr.deviance[i]), @sprintf("%.4f", Δdev[i-1]),
                           string(StatsBase.PValue(lrr.pval[i])) ]
    end
    colwidths = length.(outrows)
    max_colwidths = [maximum(view(colwidths, :, i)) for i in 1:nc]
    totwidth = sum(max_colwidths) + 2*5

    println(io, "Likelihood-ratio test: $N models fitted on $(lrr.nobs) observations")
    println(io, '─'^totwidth)

    for r in 1:nr+1
        for c in 1:nc
            cur_cell = outrows[r, c]
            cur_cell_len = length(cur_cell)

            padding = " "^(max_colwidths[c]-cur_cell_len)
            if c > 1
                padding = "  "*padding
            end

            print(io, padding)
            print(io, cur_cell)
        end
        print(io, "\n")
        r == 1 && println(io, '─'^totwidth)
    end
    print(io, '─'^totwidth)
end
