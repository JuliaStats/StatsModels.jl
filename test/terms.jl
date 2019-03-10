function mimestring(mime::Type{<:MIME}, x)
    buf=IOBuffer()
    show(buf, mime(), x)
    String(take!(buf))
end
mimestring(x) = mimestring(MIME"text/plain", x)

@testset "terms" begin

    using Statistics

    @testset "concrete_term" begin
        t = term(:aaa)
        @test string(t) == "aaa"
        @test mimestring(t) == "aaa(unknown)"

        t0 = concrete_term(t, [3, 2, 1])
        @test string(t0) == "aaa"
        @test mimestring(t0) == "aaa(continuous)"
        @test t0.mean == 2.0
        @test t0.var == var([1,2,3])
        @test t0.min == 1.0
        @test t0.max == 3.0

        t1 = concrete_term(t, [:a, :b, :c])
        @test t1.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t1) == "aaa"
        @test mimestring(t1) == "aaa(DummyCoding:3→2)"

        t3 = concrete_term(t, [:a, :b, :c], DummyCoding())
        @test t3.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t3) == "aaa"
        @test mimestring(t3) == "aaa(DummyCoding:3→2)"

        t2 = concrete_term(t, [:a, :a, :b], EffectsCoding())
        @test t2.contrasts isa StatsModels.ContrastsMatrix{EffectsCoding}
        @test mimestring(t2) == "aaa(EffectsCoding:2→1)"
        @test string(t2) == "aaa"

        t2full = concrete_term(t, [:a, :a, :b], StatsModels.FullDummyCoding())
        @test t2full.contrasts isa StatsModels.ContrastsMatrix{StatsModels.FullDummyCoding}
        @test mimestring(t2full) == "aaa(StatsModels.FullDummyCoding:2→2)"
        @test string(t2full) == "aaa"
    end
    
    @testset "term operators" begin
        a = term(:a)
        b = term(:b)
        @test a + b == (a, b)
        @test (a ~ b) == FormulaTerm(a, b)
        @test string(a~b) == "$a ~ $b"
        @test mimestring(a~b) ==
            """FormulaTerm
               Response:
                 a(unknown)
               Predictors:
                 b(unknown)"""
        @test mimestring(a ~ term(1) + b) ==
            """FormulaTerm
               Response:
                 a(unknown)
               Predictors:
                 1
                 b(unknown)"""
        @test a & b == InteractionTerm((a,b))
        @test string(a & b) == "$a & $b"
        @test mimestring(a & b) == "a(unknown) & b(unknown)"
        c = term(:c)
        @test (a+b)+c == (a,b,c)
        @test a+(b+c) == (a,b,c)
    end
end
