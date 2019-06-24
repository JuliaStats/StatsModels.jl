@testset "schemas" begin

    using StatsModels: schema, apply_schema, FullRank

    f = @formula(y ~ 1 + a + b + c + b&c)
    df = (y = rand(9), a = 1:9, b = rand(9), c = repeat(["d","e","f"], 3))
    f = apply_schema(f, schema(f, df))
    @test f == apply_schema(f, schema(f, df))

end
