@testset "schemas" begin
    import Base
    using StatsModels: schema, apply_schema, FullRank

    f = @formula(y ~ 1 + a + b + c + b & c)
    y = rand(9)
    b = rand(9)

    df = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
    f = apply_schema(f, schema(f, df))
    @test f == apply_schema(f, schema(f, df))

    df2 = (y = y, a = 1:9, b = b, c = [df.c; df.c])
    df3 = (y = y, a = 1:9, b = b, c = repeat(["a", "b", "c"], 3))
    df4 = (y = [df.y; df.y], a = [1:9; 1:9], b = [b; b], c = [df.c; df.c])
    df5 = (z = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))

    sch = schema(df, Dict(:c => DummyCoding(base="e")))
    sch2 = schema(df, Dict(:c => EffectsCoding(base="e")))

    @test schema(df) == schema(df2)
    @test schema(df) != schema(df3)
    @test schema(df) != schema(df4)
    @test schema(df) != schema(df5)
    @test sch != sch2

    @test isequal(schema(df), schema(df2))
    @test !isequal(schema(df), schema(df3))
    @test !isequal(schema(df), schema(df4))
    @test !isequal(schema(df), schema(df5))
    @test !isequal(sch, sch2)

    # @test schema(df) == schema(df3)
    # @test isequal(schema(df), schema(df3))
    #@test schema(df) != schema(df4)
    #@test isequal(schema(df), schema(df4))


end
