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

    @testset "statistics=false" begin
        f = @formula(y ~ 1 + a + b + c)
        d = (y = rand(10), a = rand(10), b = Float32.(1:10),
             c = repeat(["u","v"], 5))

        sch = schema(f, d, statistics=false)
        t = sch[term(:a)]
        @test t isa ContinuousTerm
        @test isnan(t.mean) && isnan(t.var) && isnan(t.min) && isnan(t.max)
        # the statistics keep the type they would have had
        @test sch[term(:b)] isa ContinuousTerm{Float32}
        # categorical terms are unaffected
        c1, c2 = sch[term(:c)], schema(f, d)[term(:c)]
        @test c1 isa CategoricalTerm && c1.sym == c2.sym && c1.contrasts == c2.contrasts

        # skipping statistics changes nothing else downstream
        ff = apply_schema(f, sch)
        @test modelmatrix(ff.rhs, d) == modelmatrix(apply_schema(f, schema(f, d)).rhs, d)

        # hints still work, and never see the keyword
        sch1 = schema(f, d, Dict(:a => CategoricalTerm), statistics=false)
        @test sch1[term(:a)] isa CategoricalTerm{DummyCoding}
        sch2 = schema(f, d, Dict(:a => EffectsCoding()), statistics=false)
        @test sch2[term(:a)] isa CategoricalTerm{EffectsCoding}
        # a ContinuousTerm hint skips the statistics too
        sch3 = schema(f, d, Dict(:a => ContinuousTerm), statistics=false)
        @test isnan(sch3[term(:a)].mean)
        # an AbstractTerm hint is included as is
        hint = schema(f, d)[term(:a)]
        @test schema(f, d, Dict(:a => hint), statistics=false)[term(:a)] === hint

        @test isnan(concrete_term(term(:a), [1, 2, 3], ContinuousTerm, statistics=false).mean)
        @test concrete_term(term(:a), [1, 2, 3], ContinuousTerm, statistics=true).mean == 2.0
    end

    @testset "nice errors" begin
        d = (yyy = rand(10), aaa = rand(10), bbb = repeat([:a, :b], 5))
        @test_throws ArgumentError("There isn't a variable called 'aa' in your data; the nearest names appear to be: aaa") concrete_term(Term(:aa), d, nothing)
        @test_throws ArgumentError("There isn't a variable called 'aab' in your data; the nearest names appear to be: aaa, bbb") concrete_term(Term(:aab), d, nothing)

        @test_throws ArgumentError("Column 'a' is empty.") concrete_term(Term(:a), (; a=[]), nothing)
        @test_throws ArgumentError("Column 'a' is empty.") schema((; b=[1,2], a=[]))
        
    end
    

end
