@testset "schemas" begin
    import Base
    using StatsModels: schema, apply_schema, FullRank

    f = @formula(y ~ 1 + a + b + c + b & c)
    y = rand(9)
    b = rand(9)

    df = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))
    f = apply_schema(f, schema(f, df))
    @test f == apply_schema(f, schema(f, df))

    df2 = (y = y, a = 1:9, b = b, c = repeat(["d", "e", "f"], 3))

    @test schema(df) == schema(df2)
    @test isequal(schema(df), schema(df2))
end
