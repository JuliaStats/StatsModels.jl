@testset "schemas" begin
    using StatsModels: schema, apply_schema, FullRank

    @testset "no-op apply_schema" begin
        f = @formula(y ~ 1 + a + b + c + b&c)
        df = (y = rand(9), a = 1:9, b = rand(9), c = repeat(["d","e","f"], 3))
        f = apply_schema(f, schema(f, df))
        @test f == apply_schema(f, schema(f, df))
    end

    @testset "lonely term in a tuple" begin
        d = (a = [1,1],)
        @test apply_schema(ConstantTerm(1), schema(d)) == apply_schema((ConstantTerm(1),), schema(d))
        @test apply_schema(Term(:a), schema(d)) == apply_schema((Term(:a),), schema(d))
    end

    @testset "hints" begin
        f = @formula(y ~ 1 + a)
        d = (y = rand(10), a = repeat([1,2], outer=2))

        sch = schema(f, d)
        @test sch[term(:a)] isa ContinuousTerm

        sch1 = schema(f, d, Dict(:a => CategoricalTerm))
        @test sch1[term(:a)] isa CategoricalTerm{DummyCoding}
        f1 = apply_schema(f, sch1)
        @test f1.rhs.terms[end] == sch1[term(:a)]

        sch2 = schema(f, d, Dict(:a => DummyCoding()))
        @test sch2[term(:a)] isa CategoricalTerm{DummyCoding}
        f2 = apply_schema(f, sch2)
        @test f2.rhs.terms[end] == sch2[term(:a)]

        hint = deepcopy(sch2[term(:a)])
        sch3 = schema(f, d, Dict(:a => hint))
        # if an <:AbstractTerm is supplied as hint, it's included as is
        @test sch3[term(:a)] === hint !== sch2[term(:a)]
        f3 = apply_schema(f, sch3)
        @test f3.rhs.terms[end] === hint

    end

    @testset "has_schema" begin
        using StatsModels: has_schema

        d = (y = rand(10), a = rand(10), b = repeat([:a, :b], 5))

        f = @formula(y ~ a*b)
        @test !has_schema(f)
        @test !has_schema(f.rhs)
        @test !has_schema(StatsModels.collect_matrix_terms(f.rhs))

        ff = apply_schema(f, schema(d))
        @test has_schema(ff)
        @test has_schema(ff.rhs)
        @test has_schema(StatsModels.collect_matrix_terms(ff.rhs))

        sch = schema(d)
        a, b = term.((:a, :b))
        @test !has_schema(a)
        @test has_schema(sch[a])
        @test !has_schema(b)
        @test has_schema(sch[b])

        @test !has_schema(a & b)
        @test !has_schema(a & sch[b])
        @test !has_schema(sch[a] & a)
        @test has_schema(sch[a] & sch[b])

    end

    @testset "basic hash and equality" begin
        f = @formula(y ~ 1 + a + log(b) + c + b & c)
        y = rand(9)
        b = rand(9)

        df = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
        f = apply_schema(f, schema(f, df))
        @test f == apply_schema(f, schema(f, df))

        sch1 = schema(f, df)
        sch2 = schema(f, df)
        @test sch1 == sch2
        @test sch1 !== sch2
        @test hash(sch1) == hash(sch2)

        # double categorical column c to test for invariance based on levels
        df2 = (y = y, a = 1:9, b = b, c = [df.c; df.c])
        @test schema(df) == schema(df2)
        @test hash(schema(df)) == hash(schema(df2))
        @test apply_schema(f, schema(df)) == apply_schema(f, schema(df2))

        # different levels
        df3 = (y = y, a = 1:9, b = b, c = repeat(["a", "b", "c"], 3))
        @test schema(df) != schema(df3)

        # different length, so different summary stats for continuous
        df4 = (y = [df.y; df.y], a = [1:9; 1:9], b = [b; b], c = [df.c; df.c])
        @test schema(df) != schema(df4)

        # different names for some columns
        df5 = (z = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
        @test schema(df) != schema(df5)

        # different values in continuous column so different stats
        df6 = (y = y, a = 2:10, b = b, c = repeat(["a", "b", "c"], 3))
        @test schema(df) != schema(df6)

        # different names?
        df7 = (w = y, d = 1:9, x = b, z = repeat(["d", "e", "f"], 3))
        @test schema(df) != schema(df7)

        # missing column
        df8 = (y = y, a = 1:9, c = repeat(["d", "e", "f"], 3))
        @test schema(df) != schema(df8)

        # different coding/hints
        sch = schema(df, Dict(:c => DummyCoding(base="e")))
        sch2 = schema(df, Dict(:c => EffectsCoding(base="e")))
        sch3 = schema(df, Dict(:y => DummyCoding()))
        @test sch != sch2
        @test sch != sch3
    end
end
