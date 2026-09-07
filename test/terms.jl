function mimestring(mime::Type{<:MIME}, x)
    buf=IOBuffer()
    show(buf, mime(), x)
    String(take!(buf))
end
mimestring(x) = mimestring(MIME"text/plain", x)

struct MultiTerm <: AbstractTerm
    terms::Vector{AbstractTerm}
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
        @test a + b == [a, b]
        @test (a ~ b) == FormulaTerm(a, [b])
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

        @testset "Associative property of +" begin
            a, b, c = term(:a), term(:b), term(:c)
            ab = a+b
            bc = b+c
            abc = a+b+c
            @test ab+c == abc
            @test ab+a == ab
            @test a+bc == abc
            @test b+ab == ab
            @test ab+ab == ab
            @test ab+bc == abc
        end

        @testset "Associative property of &" begin
            a, b, c = term(:a), term(:b), term(:c)
            ab = a&b
            bc = b&c
            abc = a&b&c
            @test ab&c == abc
            @test ab&a == ab
            @test a&bc == abc
            @test b&ab == ab
            @test ab&ab == ab
            @test ab&bc == abc
        end

        @testset "And-1" begin
            a, b, one, two = term(:a), term(:b), term(1), term(2)
            @test a & one == a
            @test one & a == a
            @test (a&b) & one == a&b
            @test one & (a&b) == a&b

            # two constant terms takes the first:
            @test_throws ArgumentError one & two
            @test_throws ArgumentError two & one
            @test_throws ArgumentError (a&b) & two == a&b
            @test_throws ArgumentError two & (a&b) == a&b
        end

        @testset "Tuples and singletons" begin
            a, b, c = term(:a), term(:b), term(:c)
            @test sum((a,b,c)) == a+b+c
            @test sum((a,)) == a
            @test +a == a

            @test (&)(a) == a
        end
        
    end

    @testset "uniqueness of FunctionTerms" begin
        f1 = @formula(y ~ lag(x,1) + lag(x,1))
        f2 = @formula(y ~ lag(x,1))
        f3 = @formula(y ~ lag(x,1) + lag(x,2))

        @test f1.rhs == f2.rhs
        @test f1.rhs != f3.rhs

        ## addition of two identical function terms
        @test f2.rhs + f2.rhs == f2.rhs

        ## hash is consistent with ==, so hash-based deduplication works
        @test hash(f1.rhs) == hash(f2.rhs)
        @test hash(f1) == hash(f2)
        @test length(unique([only(f2.rhs), only(f2.rhs)])) == 1
        @test length(Set([f1, f2])) == 1
        @test length(Set([term(:z) & only(f2.rhs), term(:z) & only(f2.rhs)])) == 1
    end

    @testset "flatten term vectors during apply_schema" begin
        sch = schema((a=rand(10), b=rand(10), c=rand(10)))

        terms2 = apply_schema(term.([:a, :b, :c]), sch, Nothing)
        @test terms2 isa Vector{AbstractTerm}
        @test all(t -> t isa ContinuousTerm, terms2)

        # a term that generates multiple terms after apply_schema is flattened
        mterms = AbstractTerm[term(:a), MultiTerm([term(:b), term(:c)])]
        terms3 = apply_schema(mterms, sch, Nothing)

        @test terms2 == terms3
    end

    @testset "Intercept and response traits" begin

        has_responses = [term(:y), term(1), InterceptTerm{true}(), term(:y)+term(:z),
                        term(:y) + term(0), term(:y) + InterceptTerm{false}()]
        no_responses = [term(0), InterceptTerm{false}()]

        has_intercepts = [term(1), InterceptTerm{true}()]
        no_intercepts = [term(:x), FunctionTerm(log, [term(1), term(:x)], :(log(1+x)))]
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

        for lhs in has_responses, rhs in no_intercepts
            @test hasresponse(lhs ~ rhs)
            @test !hasintercept(lhs ~ rhs)
            @test !omitsintercept(lhs ~ rhs)

            @test hasresponse(lhs ~ rhs + a)
            @test !hasintercept(lhs ~ rhs + a)
            @test !omitsintercept(lhs ~ rhs + a)
        end

        for lhs in no_responses, rhs in no_intercepts
            @test !hasresponse(lhs ~ rhs)
            @test !hasintercept(lhs ~ rhs)
            @test !omitsintercept(lhs ~ rhs)

            @test !hasresponse(lhs ~ rhs + a)
            @test !hasintercept(lhs ~ rhs + a)
            @test !omitsintercept(lhs ~ rhs + a)
        end

    end

    @testset "Term containers" begin
        using StatsModels: TermOrTerms, Term
        a, b, c = Term.((:a, :b, :c))

        # TermOrTerms - a term or a vector of terms
        @test a isa TermOrTerms
        @test [a] isa TermOrTerms
        @test [a, b] isa TermOrTerms
        @test AbstractTerm[a, b, a&b] isa TermOrTerms
        @test !([1, 2] isa TermOrTerms)

        # no methods for operators on term and tuples (=no type piracy)
        @test_throws MethodError a + ()
        @test_throws MethodError () + a
        @test_throws MethodError a & ()
        @test_throws MethodError () & a
        @test_throws MethodError a ~ ()
        @test_throws MethodError () ~ a
        @test_throws MethodError a + (a, b)
        @test_throws MethodError (a, b) + a

        # show methods
        @test "$(())" == "()"
        @test "$([a, b])" == "a + b"
        @test "$(AbstractTerm[a, a & b])" == "a + a & b"
    end

    @testset "vector of terms" begin
        using StatsModels: terms, termvars, has_schema, drop_term, cleanup,
            collect_matrix_terms, hasintercept, omitsintercept, termnames,
            InterceptTerm, ContinuousTerm, CategoricalTerm, MatrixTerm,
            InteractionTerm
        a, b, c = term(:a), term(:b), term(:c)
        one = term(1)

        @testset "+ and & on vectors" begin
            # all four (term, vector) combinations, with and without duplicates
            @test [a, b] + c == [a, b, c]
            @test [a, b] + a == [a, b]
            @test c + [a, b] == [c, a, b]
            @test a + [a, b] == [a, b]
            @test [a, b] + [b, c] == [a, b, c]
            @test [a, b] + [a, b] == [a, b]
            # concretely typed vectors hit the Vector{<:AbstractTerm} method,
            # not elementwise + from Base
            @test Term[a, b] + Term[b, c] == [a, b, c]
            @test Term[a, b] + Term[b, c] isa Vector{AbstractTerm}
            @test view([a, b, c], 1:2) + c == [a, b, c]
            # a + a is a one-element vector, not a bare term
            @test a + a == [a]
            @test a + a isa Vector{AbstractTerm}
            @test [a] + a == [a]

            # distributive rule
            @test a & [b, c] == [a & b, a & c]
            @test [a, b] & c == [a & c, b & c]
            @test [a, b] & [c, one] == [a & c, a, b & c, b]
            @test (a & [b, c]) isa Vector{AbstractTerm}

            # * expands with vectors on either side
            @test a * [b, c] == [a, b, c, a & b, a & c]
            @test [a, b] * c == [a, b, c, a & c, b & c]
        end

        @testset "~ always makes a vector rhs" begin
            f = a ~ b
            @test f.rhs == [b]
            @test f.rhs isa Vector{AbstractTerm}
            @test f.lhs == a
            # duplicates dropped and sorted by degree, without touching the input
            rhs = AbstractTerm[a & b, c, a, c, one]
            f = a ~ rhs
            @test f.rhs == [one, c, a, a & b]
            @test rhs == AbstractTerm[a & b, c, a, c, one]
            @test cleanup(a) == [a]
            @test ([a, b] ~ c) == FormulaTerm([a, b], [c])
        end

        @testset "traversal" begin
            v = AbstractTerm[one, a, b & c]
            @test terms(v) == [one, a, b, c]
            @test terms(v) isa Vector{AbstractTerm}
            @test terms(AbstractTerm[]) == AbstractTerm[]
            @test terms(MatrixTerm(v)) == terms(v)
            @test termvars(v) == [:a, :b, :c]
            @test termvars(AbstractTerm[]) == Symbol[]
            @test termvars(MatrixTerm(v)) == [:a, :b, :c]
            @test hasintercept(v) && !omitsintercept(v)
            @test !hasintercept([a, b]) && omitsintercept([term(0), a])
            @test termnames(v) == ["1", "a", "b & c"]
            @test termnames([a]) == ["a"]
            @test drop_term(v, b & c) == [one, a]
            @test drop_term(v, b & c) isa Vector{AbstractTerm}
            @test drop_term(v, term(:z)) == v
        end

        @testset "schema" begin
            d = (a=rand(10), b=rand(10), c=repeat(["u", "v"], 5))
            sch = schema(d)
            @test !has_schema([a, b])
            @test !has_schema(AbstractTerm[apply_schema(a, sch), b])
            @test has_schema(apply_schema([a, b], sch))

            # schema and apply_schema accept a vector, a lone term, and a formula
            @test schema([a, b], d).schema == schema(a + b, d).schema
            @test keys(schema(a, d).schema) == Set([a])
            @test keys(schema(AbstractTerm[one, a, b & c], d).schema) == Set([a, b, c])

            ts = apply_schema(AbstractTerm[a, b, c, a & c], sch)
            @test ts isa Vector{AbstractTerm}
            @test ts[1] isa ContinuousTerm && ts[3] isa CategoricalTerm
            @test ts[4] isa InteractionTerm
            @test ts[4].terms == [ts[1], ts[3]]
            # a lone term in a vector stays a vector; duplicates are dropped
            @test apply_schema([a], sch) == [apply_schema(a, sch)]
            @test apply_schema([a, a], sch) == [apply_schema(a, sch)]
            @test apply_schema(AbstractTerm[], sch) == AbstractTerm[]
            # the formula rhs collapses to a MatrixTerm
            f = apply_schema(term(:a) ~ b + c, sch)
            @test f.rhs isa MatrixTerm
            @test f.rhs == MatrixTerm(apply_schema([b, c], sch))
            @test width(f.rhs) == 2
        end

        @testset "modelcols, coefnames, modelmatrix" begin
            d = (a=collect(1.0:5.0), b=collect(6.0:10.0), c=repeat(["u", "v", "u", "v", "u"]))
            sch = schema(d)
            ts = apply_schema([a, b, c], sch)
            cols = modelcols(ts, d)
            @test cols isa Vector
            @test cols[1] == d.a && cols[2] == d.b
            @test size(cols[3]) == (5, 1)
            @test coefnames(ts) == ["a", "b", "c: v"]
            @test modelmatrix(ts, d) == modelmatrix(MatrixTerm(ts), d)
            @test modelmatrix(a + b, d) == [d.a d.b]
            @test modelmatrix(a, d) == reshape(d.a, :, 1)
            @test width(ts[3] & ts[1]) == 1
        end

        @testset "MatrixTerm and collect_matrix_terms" begin
            @test MatrixTerm(a) == MatrixTerm([a])
            @test MatrixTerm((a, b)) == MatrixTerm([a, b])
            @test MatrixTerm(a).terms isa Vector{AbstractTerm}
            @test collect_matrix_terms(a) == MatrixTerm(a)
            @test collect_matrix_terms(MatrixTerm(a)) == MatrixTerm(a)
            @test collect_matrix_terms([a, b]) == MatrixTerm([a, b])
            @test collect_matrix_terms(Term[a, b]) == MatrixTerm([a, b])
            @test InteractionTerm((a, b)) == InteractionTerm([a, b])
            @test InteractionTerm([a, b]).terms isa Vector{AbstractTerm}
        end

        @testset "== and hash" begin
            @test hash(MatrixTerm([a, b])) == hash(MatrixTerm((a, b)))
            @test hash(a & b) == hash(InteractionTerm([a, b]))
            @test hash(a ~ b) == hash(a ~ [b])
            @test MatrixTerm([a, b]) != MatrixTerm([b, a])
            @test a & b != b & a
            @test (a ~ b) != (b ~ a)
            @test length(Set([a ~ b + c, a ~ b + c])) == 1
            @test length(Set([MatrixTerm([a, b]), MatrixTerm([a, b])])) == 1
            @test length(unique([a & b, a & b, b & a])) == 2
        end

        @testset "empty vector of terms" begin
            e = AbstractTerm[]
            d = (y=rand(5), a=rand(5))
            @test e + a == [a] && a + e == [a] && e + e == e
            @test a & e == e && e & a == e && e & e == e
            @test a * e == [a]
            @test terms(e) == e && termvars(e) == Symbol[]
            @test has_schema(e) && !hasintercept(e) && !omitsintercept(e)
            @test termnames(e) == String[] && coefnames(e) == String[]
            @test drop_term(e, a) == e
            @test isempty(schema(e, d).schema)
            @test apply_schema(e, schema(d)) == e
            @test collect_matrix_terms(e) == MatrixTerm(e)
            @test width(MatrixTerm(e)) == 0
            @test coefnames(MatrixTerm(e)) == String[]
            @test termnames(MatrixTerm(e)) == String[]
            @test modelcols(e, d) == []
            # an empty rhs behaves like `y ~ 0`: a matrix with n rows and no columns
            f = apply_schema(term(:y) ~ e, schema(d))
            @test f.rhs == MatrixTerm(e)
            y, X = modelcols(f, d)
            @test y == d.y && size(X) == (5, 0)
            @test size(modelmatrix(e, d)) == (5, 0)
            @test modelcols(MatrixTerm(e), (y=1.0, a=2.0)) == Float64[]
            @test coefnames(f) == ("y", String[])
            @test mimestring(term(:y) ~ e) == "FormulaTerm\nResponse:\n  y(unknown)\nPredictors:"
            @test hash(e) == hash(AbstractTerm[])
            # an interaction needs at least one term
            @test_throws ArgumentError InteractionTerm(e)
            @test_throws ArgumentError InteractionTerm(())
        end

        @testset "show" begin
            @test string(AbstractTerm[]) == ""
            @test string([a]) == "a"
            @test string(MatrixTerm([a, b])) == "a + b"
            @test mimestring([a, b]) == "a(unknown)\nb(unknown)"
            @test mimestring(Term[a]) == "a(unknown)"
        end
    end

    @testset "concrete_term error messages" begin
        t = (a = [1, 2, 3], b = [0.0, 0.5, 1.0])
        @test Tables.istable(t)
        @test_throws ArgumentError concrete_term(term(:not_there), t )
    end

    @testset "sort by degree in ~" begin
        one, a, b = term.([1, :a, :b])
        for zero_deg in [one, InterceptTerm{true}(), InterceptTerm{false}()]
            @test a + zero_deg == [a, zero_deg]
            @test (a ~ a + zero_deg) == (a ~ zero_deg + a)

            @test a & b + zero_deg + a == [a & b, zero_deg, a]
            @test (a ~ a & b + zero_deg + a) == (a ~ zero_deg + a + a & b)
        end
    end

end
