@testset "schemas" begin

    using StatsModels: schema, apply_schema, FullRank

    @testset "no-op apply_schema" begin
        f = @formula(y ~ 1 + a + b + c + b&c)
        df = (y = rand(9), a = 1:9, b = rand(9), c = repeat(["d","e","f"], 3))
        f = apply_schema(f, schema(f, df))
        @test f == apply_schema(f, schema(f, df))
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
    
end
