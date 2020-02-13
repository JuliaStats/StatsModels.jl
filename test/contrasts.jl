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
    allowmissing!(d,:x)
    d[3, :x] = missing
    mf_missing = ModelFrame(@formula(y ~ x), d,
                            contrasts = Dict(:x => EffectsCoding()))
    @test ModelMatrix(mf_missing).m == [1  1
                                        1 -1
                                        1 -1
                                        1 -1
                                        1  1]
    @test coefnames(mf_missing) == ["(Intercept)"; "x: b"]

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

        @test modelmatrix(setcontrasts!(mf, x = HypothesisCoding(effects_hyp))) ≈
            modelmatrix(setcontrasts!(mf, x = EffectsCoding()))

        d2 = DataFrame(y = rand(100),
                       x = repeat([:a, :b, :c, :d], inner=25))

        sdiff_hyp = HypothesisCoding([-1 1 0 0
                                      0 -1 1 0
                                      0 0 -1 1])

        effects_hyp = HypothesisCoding([-1 3 -1 -1
                                        -1 -1 3 -1
                                        -1 -1 -1 3] ./ 4)

        f = apply_schema(@formula(y ~ 1 + x), schema(d2))

        f_sdiff = apply_schema(f, schema(d2, Dict(:x => sdiff_hyp)))
        f_effects = apply_schema(f, schema(d2, Dict(:x => effects_hyp)))

        y_means = by(d2, :x, :y => mean).y_mean
        
        y, X_sdiff = modelcols(f_sdiff, d2)
        @test X_sdiff \ y ≈ [mean(y_means); diff(y_means)]

        y, X_effects = modelcols(f_effects, d2)
        @test X_effects \ y ≈ [mean(y_means); y_means[2:end] .- mean(y_means)]

        @test X_effects ≈ modelcols(apply_schema(f.rhs,
                                                 schema(d2, Dict(:x=>EffectsCoding()))),
                                    d2)
    end
end
