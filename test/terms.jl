@testset "terms" begin

    using Statistics

    @testset "concrete instantion with schema" begin
        t = term(:aaa)
        @test string(t) == "aaa"

        t0 = schema(t, [3, 2, 1])
        @test string(t0) == "aaa (continuous)"
        @test t0.mean == 2.0
        @test t0.var == var([1,2,3])
        @test t0.min == 1.0
        @test t0.max == 3.0

        t1 = schema(t, [:a, :b, :c])
        @test t1.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t1) == "aaa (3 levels): DummyCoding(2)"

        t3 = schema(t, [:a, :b, :c], DummyCoding())
        @test t3.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t3) == "aaa (3 levels): DummyCoding(2)"

        t2 = schema(t, [:a, :a, :b], EffectsCoding())
        @test t2.contrasts isa StatsModels.ContrastsMatrix{EffectsCoding}
        @test string(t2) == "aaa (2 levels): EffectsCoding(1)"

        t2full = schema(t, [:a, :a, :b], StatsModels.FullDummyCoding())
        @test t2full.contrasts isa StatsModels.ContrastsMatrix{StatsModels.FullDummyCoding}
        @test string(t2full) == "aaa (2 levels): StatsModels.FullDummyCoding(2)"
    end
    
    @testset "term operators" begin
        a = term(:a)
        b = term(:b)
        @test a + b == (a, b)
        @test (a ~ b) == FormulaTerm(a, b)
        @test string(a~b) == "$a ~ $b"
        @test a & b == InteractionTerm((a,b))
        @test string(a&b) == "$a&$b"

        c = term(:c)
        @test (a+b)+c == (a,b,c)
        @test a+(b+c) == (a,b,c)
    end
end
