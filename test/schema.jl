@testset "schemas" begin
    using StatsModels: schema, apply_schema, FullRank

    f = @formula(y ~ 1 + a + log(b) + c + b & c)
    y = rand(9)
    b = rand(9)

    df = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
    f = apply_schema(f, schema(f, df))
    @test f == apply_schema(f, schema(f, df))

    df2 = (y = y, a = 1:9, b = b, c = [df.c; df.c])
    df3 = (y = y, a = 1:9, b = b, c = repeat(["a", "b", "c"], 3))
    df4 = (y = [df.y; df.y], a = [1:9; 1:9], b = [b; b], c = [df.c; df.c])
    df5 = (z = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
    df6 = (y = y, a = 2:10, b = b, c = repeat(["a", "b", "c"], 3))
    df7 = (w = y, d = 1:9, x = b, z = repeat(["d", "e", "f"], 3))
    df8 = (y = y, a = 1:9, c = repeat(["d", "e", "f"], 3))

    sch = schema(df, Dict(:c => DummyCoding(base="e")))
    sch2 = schema(df, Dict(:c => EffectsCoding(base="e")))

    @test schema(df) == schema(df2)
    @test apply_schema(f, schema(df)) == apply_schema(f, schema(df2))
    @test schema(df) != schema(df3)
    @test schema(df) != schema(df4)
    @test schema(df) != schema(df5)
    @test schema(df) != schema(df6)
    @test schema(df) != schema(df7)
    @test schema(df) != schema(df8)
    @test schema(df8) != schema(df)
    @test apply_schema(f, schema(df)) == apply_schema(f, schema(df5))
    @test sch != sch2

    @test isequal(schema(df), schema(df2))
    @test isequal(apply_schema(f, schema(df)), apply_schema(f, schema(df2)))
    @test !isequal(schema(df), schema(df3))
    @test !isequal(schema(df), schema(df4))
    @test !isequal(schema(df), schema(df5))
    @test !isequal(schema(df), schema(df6))
    @test !isequal(schema(df), schema(df7))
    @test !isequal(schema(df), schema(df8))
    @test !isequal(schema(df8), schema(df))
    @test isequal(apply_schema(f, schema(df)), apply_schema(f, schema(df5)))
    @test !isequal(sch, sch2)

end
