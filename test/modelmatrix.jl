@testset "Model matrix" begin
    
    using StatsBase: StatisticalModel

    using SparseArrays, DataFrames, Tables

    sparsetype = SparseMatrixCSC{Float64,Int}

    d = DataFrame(y = 1:4,
                  x1 = 5:8,
                  x2 = 9:12,
                  x3 = 13:16,
                  x4 = 17:20)
    d.x1p = categorical(d.x1)

    d_orig = deepcopy(d)
    
    x1 = [5.:8;]
    x2 = [9.:12;]
    x3 = [13.:16;]
    x4 = [17.:20;]
    f = @formula(y ~ 1 + x1 + x2)
    mf = ModelFrame(f, d)
    @test coefnames(mf) == [:Intercept, :x1, :x2]
    @test response(mf) == [1:4;]
    mm = ModelMatrix(mf)
    smm = ModelMatrix{sparsetype}(mf)
    @test mm.m[:,1] == ones(4)
    @test mm.m[:,2:3] == [x1 x2]
    @test mm.m == smm.m

    @test isa(mm.m, Matrix{Float64})
    @test isa(smm.m, sparsetype)

    f_implint = @formula(y ~ x1 + x2)
    @test ModelMatrix(ModelFrame(f_implint, d)).m == mm.m

    @test ModelMatrix(ModelFrame(f_implint, d, model=Nothing)).m == hcat(x1, x2)

    #test_group("expanding a nominal array into a design matrix of indicators for each dummy variable")

    mf = ModelFrame(@formula(y ~ 1 + x1p), d)
    mm = ModelMatrix(mf)

    @test mm.m[:,2] == [0, 1., 0, 0]
    @test mm.m[:,3] == [0, 0, 1., 0]
    @test mm.m[:,4] == [0, 0, 0, 1.]
    @test coefnames(mf)[2:end] == [Symbol("x1p: 6"), Symbol("x1p: 7"), Symbol("x1p: 8")]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    #test_group("Creating a model matrix using full formulas: y => x1 + x2, etc")

    d = deepcopy(d_orig)
    f = @formula(y ~ 1 + x1 & x2)
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m == [ones(4) x1.*x2]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    f = @formula(y ~ 1 + x1 * x2)
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m == [ones(4) x1 x2 x1.*x2]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    d.x1 = categorical(x1)
    x1e = [[0, 1, 0, 0] [0, 0, 1, 0] [0, 0, 0, 1]]
    f = @formula(y ~ 1 + x1 * x2)
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m == [ones(4) x1e x2 [0, 10, 0, 0] [0, 0, 11, 0] [0, 0, 0, 12]]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    # additional tests from Tom
    y = [1., 2, 3, 4]
    mf = ModelFrame(@formula(y ~ 1 + x2), d)
    mm = ModelMatrix(mf)
    @test mm.m == [ones(4) x2]
    @test mm.m == ModelMatrix{sparsetype}(mf).m
    @test response(mf) == y''

    d = deepcopy(d_orig)
    d.x1 = CategoricalArray{Union{Missing, Float64}}(d.x1)

    f = @formula(y ~ 1 + x2 + x3 + x3*x2)
    mm = ModelMatrix(ModelFrame(f, d))
    @test mm.m == [ones(4) x2 x3 x2.*x3]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x3*x2 + x2 + x3), d))
    @test mm.m == [ones(4) x3 x2 x2.*x3]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x1 + x2 + x3 + x4), d))
    @test mm.m[:,2] == [0, 1., 0, 0]
    @test mm.m[:,3] == [0, 0, 1., 0]
    @test mm.m[:,4] == [0, 0, 0, 1.]
    @test mm.m[:,5] == x2
    @test mm.m[:,6] == x3
    @test mm.m[:,7] == x4

    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x2 + x3 + x4), d))
    @test mm.m == [ones(4) x2 x3 x4]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x2 + x2), d))
    @test mm.m == [ones(4) x2]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x2*x3 + x2&x3), d))
    @test mm.m == [ones(4) x2 x3 x2.*x3]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x2*x3*x4), d))
    @test mm.m == [ones(4) x2 x3 x4 x2.*x3 x2.*x4 x3.*x4 x2.*x3.*x4]
    mm = ModelMatrix(ModelFrame(@formula(y ~ 1 + x2&x3 + x2*x3), d))
    @test mm.m == [ones(4) x2 x3 x2.*x3]

    f = @formula(y ~ 1 + x2 & x3 & x4)
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m == [ones(4) x2.*x3.*x4]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    f = @formula(y ~ 1 + x1 & x2 & x3)
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m[:, 2:end] == Matrix(Diagonal(x2.*x3))
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    ## Distributive property of :& over :+
    d = deepcopy(d_orig)
    f = @formula(y ~ 1 + (x1+x2) & (x3+x4))
    mf = ModelFrame(f, d)
    mm = ModelMatrix(mf)
    @test mm.m == hcat(ones(4), x1.*x3, x1.*x4, x2.*x3, x2.*x4)
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    ## Condensing nested :+ calls
    f = @formula(y ~ 1 + x1 + (x2 + (x3 + x4)))
    @test ModelMatrix(ModelFrame(f, d)).m == hcat(ones(4), x1, x2, x3, x4)


    ## Extra levels in categorical column
    mf_full = ModelFrame(@formula(y ~ 1 + x1p), d)
    mm_full = ModelMatrix(mf_full)
    @test size(mm_full) == (4,4)

    mf_sub = ModelFrame(@formula(y ~ 1 + x1p), d[2:4, :])
    mm_sub = ModelMatrix(mf_sub)
    ## should have only three rows, and only three columns (intercept plus two
    ## levels of factor) - it also catches when some levels do not occur in the data
    @test size(mm_sub) == (3,3)

    ## Missing data
    d.x1m = [5, 6, missing, 7]
    mf = ModelFrame(@formula(y ~ 1 + x1m), d)
    mm = ModelMatrix(mf)
    @test mm.m[:, 2] == d[completecases(d), :x1m]
    @test mm.m == ModelMatrix{sparsetype}(mf).m

    ## Same variable on left and right side
    mf = ModelFrame(@formula(x1 ~ x1), d)
    mm = ModelMatrix(mf)
    mm.m == response(mf)

    ## Promote non-redundant categorical terms to full rank
    @testset "non-redundant categorical terms" begin
        d = DataFrame(x = repeat([:a, :b], outer = 4),
                      y = repeat([:c, :d], inner = 2, outer = 2),
                      z = repeat([:e, :f], inner = 4))
        categorical!(d)
        cs = Dict([Symbol(name) => EffectsCoding() for name in names(d)])
        d.n = 1.:8
    
    
        ## No intercept
        mf = ModelFrame(@formula(n ~ 0 + x), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == [1 0
                       0 1
                       1 0
                       0 1
                       1 0
                       0 1
                       1 0
                       0 1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [Symbol("x: a"), Symbol("x: b")]

        ## promotion blocked when we block default model=StatisticalModel
        mf = ModelFrame(@formula(n ~ 0 + x), d, model=Nothing, contrasts=cs)
        mm = ModelMatrix(mf)
        @test all(mm.m .== ifelse.(d.x .== :a, -1, 1))
        @test coefnames(mf) == [Symbol("x: b")]


        ## No first-order term for interaction
        mf = ModelFrame(@formula(n ~ 1 + x + x&y), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m[:, 2:end] == [-1 -1  0
                                 1  0 -1
                                 -1  1  0
                                 1  0  1
                                 -1 -1  0
                                 1  0 -1
                                 -1  1  0
                                 1  0  1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [:Intercept, Symbol("x: b"), Symbol("x: a & y: d"), Symbol("x: b & y: d")]

        ## When both terms of interaction are non-redundant:
        mf = ModelFrame(@formula(n ~ 0 + x&y), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == [1 0 0 0
                       0 1 0 0
                       0 0 1 0
                       0 0 0 1
                       1 0 0 0
                       0 1 0 0
                       0 0 1 0
                       0 0 0 1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [Symbol("x: a & y: c"), Symbol("x: b & y: c"),
                                Symbol("x: a & y: d"), Symbol("x: b & y: d")]

        # only a three-way interaction: every term is promoted.
        mf = ModelFrame(@formula(n ~ 0 + x&y&z), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == Matrix(1.0I, 8, 8)
        @test mm.m == ModelMatrix{sparsetype}(mf).m
    
        # two two-way interactions, with no lower-order term. both are promoted in
        # first (both x and y), but only the old term (x) in the second (because
        # dropping x gives z which isn't found elsewhere, but dropping z gives x
        # which is found (implicitly) in the promoted interaction x&y).
        mf = ModelFrame(@formula(n ~ 0 + x&y + x&z), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == [1 0 0 0 -1  0
                       0 1 0 0  0 -1
                       0 0 1 0 -1  0
                       0 0 0 1  0 -1
                       1 0 0 0  1  0
                       0 1 0 0  0  1
                       0 0 1 0  1  0
                       0 0 0 1  0  1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [Symbol("x: a & y: c"), Symbol("x: b & y: c"),
                                Symbol("x: a & y: d"), Symbol("x: b & y: d"),
                                Symbol("x: a & z: f"), Symbol("x: b & z: f")]
    
        # ...and adding a three-way interaction, only the shared term (x) is promoted.
        # this is because dropping x gives y&z which isn't present, but dropping y or z
        # gives x&z or x&z respectively, which are both present.
        mf = ModelFrame(@formula(n ~ 0 + x&y + x&z + x&y&z), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == [1 0 0 0 -1  0  1  0
                       0 1 0 0  0 -1  0  1
                       0 0 1 0 -1  0 -1  0
                       0 0 0 1  0 -1  0 -1
                       1 0 0 0  1  0 -1  0
                       0 1 0 0  0  1  0 -1
                       0 0 1 0  1  0  1  0
                       0 0 0 1  0  1  0  1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [Symbol("x: a & y: c"), Symbol("x: b & y: c"),
                                Symbol("x: a & y: d"), Symbol("x: b & y: d"),
                                Symbol("x: a & z: f"), Symbol("x: b & z: f"),
                                Symbol("x: a & y: d & z: f"), Symbol("x: b & y: d & z: f")]
    
        # two two-way interactions, with common lower-order term. the common term x is
        # promoted in both (along with lower-order term), because in every case, when
        # x is dropped, the remaining terms (1, y, and z) aren't present elsewhere.
        mf = ModelFrame(@formula(n ~ 0 + x + x&y + x&z), d, contrasts=cs)
        mm = ModelMatrix(mf)
        @test mm.m == [1 0 -1  0 -1  0
                       0 1  0 -1  0 -1
                       1 0  1  0 -1  0
                       0 1  0  1  0 -1
                       1 0 -1  0  1  0
                       0 1  0 -1  0  1
                       1 0  1  0  1  0
                       0 1  0  1  0  1]
        @test mm.m == ModelMatrix{sparsetype}(mf).m
        @test coefnames(mf) == [Symbol("x: a"), Symbol("x: b"),
                                Symbol("x: a & y: d"), Symbol("x: b & y: d"),
                                Symbol("x: a & z: f"), Symbol("x: b & z: f")]


        ## FAILS: When both terms are non-redundant and intercept is PRESENT
        ## (not fully redundant). Ideally, would drop last column. Might make sense
        ## to warn about this, and suggest recoding x and y into a single variable.
        mf = ModelFrame(@formula(n ~ 1 + x&y), d[1:4, :], contrasts=cs)
        @test_broken ModelMatrix(mf).m == [1 1 0 0
                                           1 0 1 0
                                           1 0 0 1
                                           1 0 0 0]
        @test_broken coefnames(mf) == [Symbol("x: a & y: c"), Symbol("x: b & y: c"),
                                       Symbol("x: a & y: d"), Symbol("x: b & y: d")]
    
        ## note that R also does not detect this automatically. it's left to glm et al.
        ## to detect numerically when the model matrix is rank deficient, which is hard
        ## to do correctly.
        # > d = data.frame(x = factor(c(1, 2, 1, 2)), y = factor(c(3, 3, 4, 4)))
        # > model.matrix(~ 1 + x:y, d)
        #   (Intercept) x1:y3 x2:y3 x1:y4 x2:y4
        # 1           1     1     0     0     0
        # 2           1     0     1     0     0
        # 3           1     0     0     1     0
        # 4           1     0     0     0     1

    end

    @testset "arbitrary functions in formulae" begin
        d = deepcopy(d_orig)
        mf = ModelFrame(@formula(y ~ log(x1)), d, model=Nothing)
        @test coefnames(mf) == [Symbol("log(x1)")]
        mm = ModelMatrix(mf)
        @test all(mm.m .== log.(x1))

        # | is not special in base formula:
        d = DataFrame(x = [1,2,3], y = [4,5,6])
        mf = ModelFrame(@formula(y ~ 1 + (1 | x)), d)
        @test coefnames(mf) == [:Intercept, Symbol("1 | x")]

        mf = ModelFrame(@formula(y ~ 0 + (1 | x)), d)
        @test all(ModelMatrix(mf).m .== float.(1 .| d.x))
        @test coefnames(mf) == [Symbol("1 | x")]
    end



    # Ensure X is not a view on df column
    d = DataFrame(x = [1.0,2.0,3.0], y = [4.0,5.0,6.0])
    mf = ModelFrame(@formula(y ~ 0 + x), d)
    X = ModelMatrix(mf).m
    X[1] = 0.0
    @test mf.data[:x][1] === 1.0

    # Ensure string columns are supported
    d1 = DataFrame(A = 1:4, B = categorical(["M", "F", "F", "M"]))
    d2 = DataFrame(A = 1:4, B = ["M", "F", "F", "M"])
    d3 = DataFrame(Any[1:4, ["M", "F", "F", "M"]], [:A, :B])

    M1 = ModelMatrix(ModelFrame(@formula(A ~ B), d1))
    M2 = ModelMatrix(ModelFrame(@formula(A ~ B), d2))
    M3 = ModelMatrix(ModelFrame(@formula(A ~ B), d3))

    @test (M1.m, M1.assign) == (M2.m, M2.assign) == (M3.m, M3.assign)

    @testset "row-wise model matrix construction" begin
        d = DataFrame(r = rand(8),
                      w = rand(8),
                      x = repeat([:a, :b], outer = 4),
                      y = repeat([:c, :d], inner = 2, outer = 2),
                      z = repeat([:e, :f], inner = 4))
    
        f = apply_schema(@formula(r ~ 1 + w*x*y*z), schema(d))
        modelmatrix(f, d)
        @test reduce(vcat, last.(modelcols.(Ref(f), Tables.rowtable(d)))') == modelmatrix(f,d)
    end

    @testset "modelmatrix and response set schema if needed" begin
        d = DataFrame(r = rand(8),
                      w = rand(8),
                      x = repeat([:a, :b], outer = 4),
                      y = repeat([:c, :d], inner = 2, outer = 2),
                      z = repeat([:e, :f], inner = 4))
    
        f = @formula(r ~ 1 + w*x*y*z)

        mm1 = modelmatrix(f, d)
        mm2 = modelmatrix(apply_schema(f, schema(d)), d)
        @test mm1 == mm2

        r1 = response(f, d)
        r2 = response(apply_schema(f, schema(d)), d)
        @test r1 == r2
    end

    @testset "setcontrasts!" begin
        @testset "#95" begin
            tbl = (Y = randn(8),
                   A = repeat(['N','Y'], outer=4),
                   B=repeat(['-','+'], inner=2, outer=2),
                   C=repeat(['L','H'], inner=4))

            contrasts = Dict(:A=>HelmertCoding(), :B=>HelmertCoding(), :C=>HelmertCoding())
                                                  
                                                  

            mf = ModelFrame(@formula(Y ~ 1 + A*B*C), tbl)
            mf_helm = ModelFrame(@formula(Y ~ 1 + A*B*C), tbl, contrasts = contrasts)

            @test size(modelmatrix(mf)) == size(modelmatrix(mf_helm))
            
            mf_helm2 = setcontrasts!(ModelFrame(@formula(Y ~ 1 + A*B*C), tbl), contrasts)

            @test size(modelmatrix(mf)) == size(modelmatrix(mf_helm2))
            @test modelmatrix(mf_helm) == modelmatrix(mf_helm2)
            
        end
    end

    @testset "#136" begin
        t = (x = rand(100), y = randn(100));
        f = @formula(y ~ x)
        @test_throws ArgumentError modelcols(f, t)
    end

    @testset "#185 - interactions of scalar terms for row tables" begin
        t = (a = rand(10), b = rand(10), c = rand(10))
        f = apply_schema(@formula(0 ~ a&b&c), schema(t))
        @test vec(modelcols(f.rhs, t)) == modelcols.(Ref(f.rhs), Tables.rowtable(t))
    end
    
end
