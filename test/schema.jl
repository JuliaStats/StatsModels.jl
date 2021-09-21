@testset "schemas" begin
    using StatsModels: schema, apply_schema, FullRank

    f = @formula(y ~ 1 + a + log(b) + c + b & c)
    y = rand(9)
    b = rand(9)

    df = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
    f = apply_schema(f, schema(f, df))
    @test f == apply_schema(f, schema(f, df))

    @testset "basic hash and equality" begin
        sch1 = schema(f, df)
        sch2 = schema(f, df)
        @test sch1 == sch2
        @test sch1 !== sch2
        @test hash(sch1) == hash(sch2)
    end

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
