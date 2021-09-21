function mimestring(mime::Type{<:MIME}, x)
    buf=IOBuffer()
    show(buf, mime(), x)
    String(take!(buf))
end
mimestring(x) = mimestring(MIME"text/plain", x)

struct MultiTerm <: AbstractTerm
    terms::StatsModels.TupleTerm
end
StatsModels.apply_schema(mt::MultiTerm, sch::StatsModels.Schema, Mod::Type) =
    apply_schema.(mt.terms, Ref(sch), Mod)


@testset "terms" begin

    using Statistics

    @testset "concrete_term" begin
        t = term(:aaa)
        ts = term("aaa")
        @test t == ts
        @test string(t) == "aaa"
        @test mimestring(t) == "aaa(unknown)"

        t0 = concrete_term(t, [3, 2, 1])
        @test string(t0) == "aaa"
        @test mimestring(t0) == "aaa(continuous)"
        @test t0.mean == 2.0
        @test t0.var == var([1,2,3])
        @test t0.min == 1.0
        @test t0.max == 3.0
        @test t0 == concrete_term(t, [3, 2, 1])
        @test hash(t0) == hash(concrete_term(t, [3, 2, 1]))

        t1 = concrete_term(t, [:a, :b, :c])
        @test t1.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t1) == "aaa"
        @test mimestring(t1) == "aaa(DummyCoding:3→2)"
        @test t1 == concrete_term(t, [:a, :b, :c])
        @test t1 !== concrete_term(t, [:a, :b, :c])
        @test hash(t1) == hash(concrete_term(t, [:a, :b, :c]))

        t3 = concrete_term(t, [:a, :b, :c], DummyCoding())
        @test t3.contrasts isa StatsModels.ContrastsMatrix{DummyCoding}
        @test string(t3) == "aaa"
        @test mimestring(t3) == "aaa(DummyCoding:3→2)"
        @test t1 == t3
        @test hash(t1) == hash(t3)

        t2 = concrete_term(t, [:a, :a, :b], EffectsCoding())
        @test t2.contrasts isa StatsModels.ContrastsMatrix{EffectsCoding}
        @test mimestring(t2) == "aaa(EffectsCoding:2→1)"
        @test string(t2) == "aaa"
        @test t2 == concrete_term(t, [:a, :a, :b], EffectsCoding())
        @test t1 != t2

        t2full = concrete_term(t, [:a, :a, :b], StatsModels.FullDummyCoding())
        @test t2full.contrasts isa StatsModels.ContrastsMatrix{StatsModels.FullDummyCoding}
        @test mimestring(t2full) == "aaa(StatsModels.FullDummyCoding:2→2)"
        @test string(t2full) == "aaa"
        @test t1 != t2full
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
        ab = a+b
        bc = b+c
        abc = a+b+c
        @test ab+c == abc
        @test ab+a == ab
        @test a+bc == abc
        @test b+ab == ab
        @test ab+ab == ab
        @test ab+bc == abc
        @test sum((a,b,c)) == abc
        @test sum((a,)) == a
        @test +a == a
    end

    @testset "expand nested tuples of terms during apply_schema" begin
        sch = schema((a=rand(10), b=rand(10), c=rand(10)))

        # nested tuples of terms are expanded by apply_schema
        terms = (term(:a), (term(:b), term(:c)))
        terms2 = apply_schema(terms, sch, Nothing)
        @test terms2 isa NTuple{3, ContinuousTerm}
        @test terms2 == apply_schema(term.((:a, :b, :c)), sch, Nothing)

        # a term that generates multiple terms after apply_schema
        mterms = (terms[1], MultiTerm(terms[2]))
        terms3 = apply_schema(mterms, sch, Nothing)

        @test terms2 == terms3
    end

    @testset "Intercept and response traits" begin

        has_responses = [term(:y), term(1), InterceptTerm{true}(), term(:y)+term(:z),
                        term(:y) + term(0), term(:y) + InterceptTerm{false}()]
        no_responses = [term(0), InterceptTerm{false}()]

        has_intercepts = [term(1), InterceptTerm{true}()]
        omits_intercepts = [term(0), term(-1), InterceptTerm{false}()]

        using StatsModels: hasresponse, hasintercept, omitsintercept

        a = term(:a)

        for lhs in has_responses, rhs in has_intercepts
            @test hasresponse(lhs ~ rhs)
            @test hasintercept(lhs ~ rhs)
            @test !omitsintercept(lhs ~ rhs)

            @test hasresponse(lhs ~ rhs + a)
            @test hasintercept(lhs ~ rhs + a)
            @test !omitsintercept(lhs ~ rhs + a)

        end

        for lhs in no_responses, rhs in has_intercepts
            @test !hasresponse(lhs ~ rhs)
            @test hasintercept(lhs ~ rhs)
            @test !omitsintercept(lhs ~ rhs)

            @test !hasresponse(lhs ~ rhs + a)
            @test hasintercept(lhs ~ rhs + a)
            @test !omitsintercept(lhs ~ rhs + a)
        end

        for lhs in has_responses, rhs in omits_intercepts
            @test hasresponse(lhs ~ rhs)
            @test !hasintercept(lhs ~ rhs)
            @test omitsintercept(lhs ~ rhs)

            @test hasresponse(lhs ~ rhs + a)
            @test !hasintercept(lhs ~ rhs + a)
            @test omitsintercept(lhs ~ rhs + a)
        end

        for lhs in no_responses, rhs in omits_intercepts
            @test !hasresponse(lhs ~ rhs)
            @test !hasintercept(lhs ~ rhs)
            @test omitsintercept(lhs ~ rhs)

            @test !hasresponse(lhs ~ rhs + a)
            @test !hasintercept(lhs ~ rhs + a)
            @test omitsintercept(lhs ~ rhs + a)
        end

    end

    @testset "equality of function terms" begin
        # for now, we use `@formula` to construct the function terms
        f1 = @formula(0 ~ (1 | x)).rhs
        f2 = @formula(0 ~ (1 | x)).rhs
        @test f1 !== f2
        @test f1 == f2
        @test hash(f1) == hash(f2)

        f3 = @formula(0 ~ (1 % x)).rhs
        @test f1 != f3
        @test hash(f1) != hash(f3)
        
        f4 = @formula(0 ~ (x | 1)).rhs
        @test f1 != f4
        @test hash(f1) != hash(f4)

        f5 = @formula(0 ~ (1 & y | x)).rhs
        @test f1 != f5
        @test hash(f1) != hash(f5)
    end

    @testset "uniqueness of FunctionTerms" begin
        f1 = @formula(y ~ lag(x,1) + lag(x,1))
        f2 = @formula(y ~ lag(x,1))
        f3 = @formula(y ~ lag(x,1) + lag(x,2))

        @test f1.rhs == f2.rhs
        @test f1.rhs != f3.rhs

        ## addition of two identical function terms
        @test f2.rhs + f2.rhs == f2.rhs
    end

    @testset "Tuple terms" begin
        using StatsModels: TermOrTerms, TupleTerm, Term
        a, b, c = Term.((:a, :b, :c))

        # TermOrTerms - one or more AbstractTerms (if more, a tuple)
        # empty tuples are never terms
        @test !(() isa TermOrTerms)
        @test (a, ) isa TermOrTerms
        @test (a, b) isa TermOrTerms
        @test (a, b, a&b) isa TermOrTerms
        @test !(((), a) isa TermOrTerms)
        # can't contain further tuples
        @test !((a, (a,), b) isa TermOrTerms)

        # a tuple of AbstractTerms OR Tuples of one or more terms
        # empty tuples are never terms
        @test !(() isa TupleTerm)
        @test (a, ) isa TupleTerm
        @test (a, b) isa TupleTerm
        @test (a, b, a&b) isa TupleTerm
        @test !(((), a) isa TupleTerm)
        @test (((a,), a) isa TupleTerm)

        # no methods for operators on term and empty tuple (=no type piracy)
        @test_throws MethodError a + ()
        @test_throws MethodError () + a
        @test_throws MethodError a & ()
        @test_throws MethodError () & a
        @test_throws MethodError a ~ ()
        @test_throws MethodError () ~ a

        # show methods of empty tuples preserved
        @test "$(())" == "()"
        @test "$((a,b))" == "a + b"
        @test "$((a, ()))" == "(a, ())"
    end

    @testset "concrete_term error messages" begin
        t = (a = [1, 2, 3], b = [0.0, 0.5, 1.0])
        @test Tables.istable(t)
        @test_throws ArgumentError concrete_term(term(:not_there), t )
    end

end
