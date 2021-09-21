@testset "contrasts" begin

    d = DataFrame(y = rand(6),
                  x = [:b, :a, :c, :a, :a, :b])

    mf = ModelFrame(@formula(y ~ x), d)

    ## testing equality of ContrastsMatrix
    should_equal = [ContrastsMatrix(DummyCoding(), [:a, :b, :c]),
                    ContrastsMatrix(DummyCoding(base=:a), [:a, :b, :c]),
                    ContrastsMatrix(DummyCoding(base=:a, levels=[:a, :b, :c]), [:a, :b, :c]),
                    ContrastsMatrix(DummyCoding(levels=[:a, :b, :c]), [:a, :b, :c])]

    for c in should_equal
        @test mf.schema[term(:x)].contrasts == c
        @test hash(mf.schema[term(:x)].contrasts) == hash(c)
    end

    should_not_equal = [ContrastsMatrix(EffectsCoding(), [:a, :b, :c]),
                        ContrastsMatrix(DummyCoding(), [:b, :c]),
                        ContrastsMatrix(DummyCoding(), [:b, :c, :a]),
                        ContrastsMatrix(DummyCoding(), [:b, :c, :a]),
                        ContrastsMatrix(DummyCoding(), [:b, :c, :a]),
                        ContrastsMatrix(DummyCoding(base=:b), [:a, :b, :c]),
                        ContrastsMatrix(DummyCoding(base=:a, levels=[:b, :a, :c]), [:a, :b, :c])]

    for c in should_not_equal
        @test mf.schema[term(:x)].contrasts != c
    end


    # Dummy coded contrasts by default:
    @test ModelMatrix(mf).m == [1  1  0
                                1  0  0
                                1  0  1
                                1  0  0
                                1  0  0
                                1  1  0]
    @test coefnames(mf) == ["(Intercept)"; "x: b"; "x: c"]

    mmm = ModelMatrix(mf).m
    setcontrasts!(mf, x = DummyCoding())
    @test ModelMatrix(mf).m == mmm

    setcontrasts!(mf, x = EffectsCoding())
    @test ModelMatrix(mf).m == [1  1  0
                                1 -1 -1
                                1  0  1
                                1 -1 -1
                                1 -1 -1
                                1  1  0]
    @test coefnames(mf) == ["(Intercept)"; "x: b"; "x: c"]

    # change base level of contrast
    setcontrasts!(mf, x = EffectsCoding(base = :b))
    @test ModelMatrix(mf).m == [1 -1 -1
                                1  1  0
                                1  0  1
                                1  1  0
                                1  1  0
                                1 -1 -1]
    @test coefnames(mf) == ["(Intercept)"; "x: a"; "x: c"]

    # change levels of contrast
    setcontrasts!(mf, x = EffectsCoding(levels = [:c, :b, :a]))
    @test ModelMatrix(mf).m == [1  1  0
                                1  0  1
                                1 -1 -1
                                1  0  1
                                1  0  1
                                1  1  0]
    @test coefnames(mf) == ["(Intercept)"; "x: b"; "x: a"]


    # change levels and base level of contrast
    setcontrasts!(mf, x = EffectsCoding(levels = [:c, :b, :a], base = :a))
    @test ModelMatrix(mf).m == [1  0  1
                                1 -1 -1
                                1  1  0
                                1 -1 -1
                                1 -1 -1
                                1  0  1]
    @test coefnames(mf) == ["(Intercept)"; "x: c"; "x: b"]
    
    # respect order of levels
    
    data = DataFrame(x = levels!(categorical(['A', 'B', 'C', 'C', 'D']), ['C', 'B', 'A', 'D']))
    f = apply_schema(@formula(x ~ 1), schema(data))
    @test modelcols(f.lhs, data) == [0 1 0; 1 0 0; 0 0 0; 0 0 0; 0 0 1]

    # Helmert coded contrasts
    setcontrasts!(mf, x = HelmertCoding())
    @test ModelMatrix(mf).m == [1  1 -1
                                1 -1 -1
                                1  0  2
                                1 -1 -1
                                1 -1 -1
                                1  1 -1]
    @test coefnames(mf) == ["(Intercept)"; "x: b"; "x: c"]

    # Mismatching types of data and contrasts levels throws an error:
    @test_throws ArgumentError setcontrasts!(mf, x = EffectsCoding(levels = ["a", "b", "c"]))

    # Missing data is handled gracefully, dropping columns when a level is lost
    dm = deepcopy(d)
    allowmissing!(dm,:x)
    dm[3, :x] = missing
    mf_missing = ModelFrame(@formula(y ~ x), dm,
                            contrasts = Dict(:x => EffectsCoding()))
    @test ModelMatrix(mf_missing).m == [1  1
                                        1 -1
                                        1 -1
                                        1 -1
                                        1  1]
    @test coefnames(mf_missing) == ["(Intercept)"; "x: b"]

    # Sequential difference coding
    setcontrasts!(mf, x = SeqDiffCoding())
    seqdiff_contr = pinv([-1 1 0
                          0 -1 1]);
    @test ModelMatrix(mf).m ≈ hcat(ones(6), seqdiff_contr[[2, 1, 3, 1, 1, 2], :])

    # Things that are bad to do:
    # Applying contrasts that only have a subset of data levels:
    @test_throws ArgumentError setcontrasts!(mf, x = EffectsCoding(levels = [:a, :b]))
    # Applying contrasts that expect levels not found in data:
    @test_throws ArgumentError setcontrasts!(mf, x = EffectsCoding(levels = [:a, :b, :c, :d]))
    # Asking for base level that's not found in data
    @test_throws ArgumentError setcontrasts!(mf, x = EffectsCoding(base = :e))

    # Manually specified contrasts
    contrasts = [0  1
                 -1 -.5
                 1  -.5]
    setcontrasts!(mf, x = StatsModels.ContrastsCoding(contrasts))
    @test ModelMatrix(mf).m == [1 -1 -.5
                                1  0  1
                                1  1 -.5
                                1  0  1
                                1  0  1
                                1 -1 -.5]

    contrasts2 = [1 0
                  1 1
                  0 1]
    setcontrasts!(mf, x = StatsModels.ContrastsCoding(contrasts2))
    @test ModelMatrix(mf).m == [1  1  1
                                1  1  0
                                1  0  1
                                1  1  0
                                1  1  0
                                1  1  1]


    hypotheses2 = pinv(contrasts2)
    # need labels for hypothesis coding
    # TODO for a future release, make this an error
    # @test_throws ArgumentError HypothesisCoding(hypotheses2)

    hyp_labels = ["2a+b-c", "-a+b+2c"]
    setcontrasts!(mf, x = HypothesisCoding(hypotheses2, labels=hyp_labels))
    @test ModelMatrix(mf).m ≈ [1  1  1
                               1  1  0
                               1  0  1
                               1  1  0
                               1  1  0
                               1  1  1]

    # different results for non-orthogonal hypotheses/contrasts:
    hypotheses3 = [1 1 0
                   0 1 1]
    hyp_labels3 = ["a+b", "b+c"]
    hc3 = HypothesisCoding(hypotheses3, labels=hyp_labels3)
    setcontrasts!(mf, x = hc3)
    @test !(ModelMatrix(mf).m ≈ [1  1  1
                                 1  1  0
                                 1  0  1
                                 1  1  0
                                 1  1  0
                                 1  1  1])

    # accepts <:AbstractMatrix
    hypotheses4 = hcat([1, 1, 0], [0, 1, 1])'
    hc4 = HypothesisCoding(hypotheses4, labels=hyp_labels3)
    @test hc4.contrasts ≈ hc3.contrasts

    # specify labels via Vector{Pair}
    hc5 = HypothesisCoding(["a_and_b" => [1, 1, 0], "b_and_c" => [0, 1, 1]])
    @test hc5.contrasts[:, 1] ≈ hc3.contrasts[:,1]
    @test hc5.contrasts[:, 2] ≈ hc3.contrasts[:,2]
    @test hc5.labels == ["a_and_b", "b_and_c"]

    # throw argument error if number of levels mismatches
    @test_throws ArgumentError setcontrasts!(mf, x = StatsModels.ContrastsCoding(contrasts[1:2, :]))
    @test_throws ArgumentError setcontrasts!(mf, x = StatsModels.ContrastsCoding(hcat(contrasts, contrasts)))

    # contrasts types must be instantiated (should throw ArgumentError, currently
    # MethodError on apply_schema)
    @test_broken setcontrasts!(mf, x = DummyCoding)

    @testset "hypothesis coding" begin

        # to get the scaling right, divide by three (because three levels)
        effects_hyp = [-1 2 -1
                       -1 -1 2] ./ 3

        @test modelmatrix(setcontrasts!(mf,
                                        x = HypothesisCoding(effects_hyp,
                                                             labels=levels(d.x)[2:end]))) ≈
            modelmatrix(setcontrasts!(mf, x = EffectsCoding()))

        d2 = DataFrame(y = rand(100),
                       x = repeat([:a, :b, :c, :d], inner=25))

        sdiff_hyp = HypothesisCoding([-1 1 0 0
                                      0 -1 1 0
                                      0 0 -1 1],
                                     labels = ["b-a", "c-b", "d-c"])

        effects_hyp = HypothesisCoding([-1 3 -1 -1
                                        -1 -1 3 -1
                                        -1 -1 -1 3] ./ 4,
                                       labels = levels(d2.x)[2:end])

        f = apply_schema(@formula(y ~ 1 + x), schema(d2))

        f_sdiff = apply_schema(f, schema(d2, Dict(:x => sdiff_hyp)))
        f_effects = apply_schema(f, schema(d2, Dict(:x => effects_hyp)))

        y_means = combine(groupby(d2, :x), :y => mean).y_mean
        
        y, X_sdiff = modelcols(f_sdiff, d2)
        @test X_sdiff \ y ≈ [mean(y_means); diff(y_means)]

        y, X_effects = modelcols(f_effects, d2)
        @test X_effects \ y ≈ [mean(y_means); y_means[2:end] .- mean(y_means)]

        @test X_effects ≈ modelcols(apply_schema(f.rhs,
                                                 schema(d2, Dict(:x=>EffectsCoding()))),
                                    d2)
    end

    @testset "hypothesis_matrix" begin
        using StatsModels: contrasts_matrix, hypothesis_matrix, needs_intercept

        cmat = contrasts_matrix(DummyCoding(), 1, 4)
        @test needs_intercept(cmat) == true
        cmat1 = hypothesis_matrix(cmat)
        @test cmat1 ≈
            [ 1 0 0 0
             -1 1 0 0
             -1 0 1 0
             -1 0 0 1]
        @test eltype(cmat1) <: Integer
        @test eltype(hypothesis_matrix(cmat1, tolerance=0)) == eltype(cmat)
        @test eltype(hypothesis_matrix(cmat1, tolerance=0.0)) == eltype(cmat)

        # incorrect interpretation without considering intercept:
        @test hypothesis_matrix(cmat, intercept=false) ≈
            [0 1 0 0
             0 0 1 0
             0 0 0 1]
        

        cmat2 = contrasts_matrix(HelmertCoding(), 1, 4)
        @test needs_intercept(cmat2) == false
        hmat2 = hypothesis_matrix(cmat2) 
        @test hmat2 ≈
            [-1/2   1/2   0    0
             -1/6  -1/6   1/3  0
             -1/12 -1/12 -1/12 1/4]

        @test eltype(hmat2) <: Rational
        
        @test hypothesis_matrix(cmat2, intercept=true) ≈
            vcat([1/4 1/4 1/4 1/4], hmat2)

        cmat3 = [-1. -1
                  1   0
                  0   1]
        @test needs_intercept(cmat3) == false
        cmat3p = copy(cmat3)
        cmat3p[1] += 1e-3
        @test needs_intercept(cmat3p) == true
    end

    @testset "levels and baselevel" begin
        using DataAPI: levels
        using StatsModels: baselevel, FullDummyCoding, ContrastsCoding

        levs = [:a, :b, :c, :d]
        base = [:c]
        for C in [DummyCoding, EffectsCoding, HelmertCoding]
            c = C()
            @test levels(c) == nothing
            @test baselevel(c) == nothing

            c = C(levels=levs)
            @test levels(c) == levs
            @test baselevel(c) == nothing

            c = C(base=base)
            @test levels(c) == nothing
            @test baselevel(c) == base

            c = C(levels=levs, base=base)
            @test levels(c) == levs
            @test baselevel(c) == base
        end

        c = SeqDiffCoding()
        @test baselevel(c) == nothing
        @test levels(c) == nothing

        c = SeqDiffCoding(levels=levs)
        @test baselevel(c) == levs[1]
        @test levels(c) == levs

        c = @test_logs((:warn,
                        "`base=` kwarg for `SeqDiffCoding` has no effect and is deprecated. " *
                        "Specify full order of levels using `levels=` instead"),
                       SeqDiffCoding(base=base))
        @test baselevel(c) == nothing
        @test levels(c) == nothing

        c = SeqDiffCoding(base=base, levels=levs)
        @test baselevel(c) == levs[1]
        @test levels(c) == levs

        c = FullDummyCoding()
        @test baselevel(c) == nothing
        @test levels(c) == nothing

        @test_throws MethodError FullDummyCoding(levels=levs)
        @test_throws MethodError FullDummyCoding(base=base)

        c = HypothesisCoding(rand(3,4))
        @test baselevel(c) == levels(c) == nothing
        c = HypothesisCoding(rand(3,4), levels=levs)
        @test baselevel(c) == nothing
        @test levels(c) == levs
        # no notion of base level for HypothesisCoding
        @test_throws MethodError HypothesisCoding(rand(3,4), base=base)

        c = ContrastsCoding(rand(4,3))
        @test baselevel(c) == levels(c) == nothing
        c = ContrastsCoding(rand(4,3), levels=levs)
        @test baselevel(c) == nothing
        @test levels(c) == levs
        # no notion of base level for ContrastsCoding
        @test_throws MethodError ContrastsCoding(rand(4,3), base=base)
        
    end

    @testset "Non-unique levels" begin
        @test_throws ArgumentError ContrastsMatrix(DummyCoding(), ["a", "a", "b"])
    end

    @testset "other string types" begin
        using CSV

        using StatsModels: ContrastsMatrix
        using DataAPI: levels

        x = ["a", "b", "c", "a", "a", "b"]
        io = IOBuffer()
        tab = CSV.write(io, (; x=x, ))
        seekstart(io)
        x1 = Tables.columntable(CSV.File(io)).x
        # this doesn't work w/ Julia < 1.3 because of WeakRefStrings compat
        # x1 = WeakRefStrings.String1.(x)
        x1_levs = levels(x1)

        @test issetequal(x, x1)

        c1 = ContrastsMatrix(DummyCoding(), x1_levs)
        c = ContrastsMatrix(DummyCoding(levels=["a", "b", "c"]), x1_levs)
        @test c == c1
        @test eltype(c.levels) == eltype(c1.levels) != eltype(c.contrasts.levels)

        @test_throws ArgumentError ContrastsMatrix(DummyCoding(levels=[1, 2, 3]), x1_levs)
    end
    
end
