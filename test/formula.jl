@testset "formula" begin

    using StatsModels: hasresponse, hasintercept

    y, x1, x2, x3, a, b, c, onet = term(:y, :x1, :x2, :x3, :a, :b, :c, 1)

    ## totally empty
    @test_broken t = @eval @formula $(:($nothing ~ 0))
    @test_broken hasresponse(t) == false
    @test_broken hasintercept(t) == false
    @test_broken t.rhs == ConstantTerm(0)
    @test_broken issetequal(terms(t), [ConstantTerm(0)])

    ## empty RHS
    t = @formula(y ~ 0)
    @test hasintercept(t) == false
    @test t.rhs == ConstantTerm(0)
    @test issetequal(terms(t), term(:y, 0))
    t = @formula(y ~ -1)
    @test hasintercept(t) == false

    ## intercept-only
    t = @formula(y ~ 1)
    @test hasresponse(t) == true
    @test hasintercept(t) == true
    @test t.rhs == onet
    @test issetequal(terms(t), (onet, y))

    ## terms add
    t = @formula(y ~ 1 + x1 + x2)
    @test hasintercept(t) == true
    @test t.rhs == (onet, x1, x2)
    @test issetequal(terms(t), [y, onet, x1, x2])

    ## implicit intercept behavior: NO intercept after @formula
    t = @formula(y ~ x1 + x2)
    @test hasintercept(t) == false
    @test t.rhs == (x1, x2)
    @test issetequal(terms(t), [y, x1, x2])

    ## no intercept
    t = @formula(y ~ 0 + x1 + x2)
    @test hasintercept(t) == false
    @test t.rhs == term(0, :x1, :x2)

    t = @formula(y ~ x1 & x2)
    @test t.rhs == x1&x2
    @test issetequal(terms(t), [y, x1, x2])

    ## `*` expansion
    t = @formula(y ~ x1 * x2)
    @test t.rhs == (x1, x2, x1&x2)
    @test issetequal(terms(t), [y, x1, x2])

    ## associative rule:
    ## +
    t = @formula(y ~ x1 + x2 + x3)
    @test t.rhs == (x1, x2, x3)

    ## &
    t = @formula(y ~ x1 & x2 & x3)
    @test t.rhs == x1&x2&x3
    @test issetequal(terms(t), [y, x1, x2, x3])

    ## distributive property of + and &
    t = @formula(y ~ x1 & (x2 + x3))
    @test t.rhs == (x1&x2, x1&x3)
    @test issetequal(terms(t), [y, x1, x2, x3])
    
    ## ordering of interaction terms is preserved across distributive
    t = @formula(y ~ (x2 + x3) & x1)
    @test t.rhs == x2&x1 + x3&x1

    ## distributive with *
    t = @formula(y ~ (a + b) * c)
    @test t.rhs == (a, b, c, a&c, b&c)

    ## three-way *
    t = @formula(y ~ a * b * c)
    @test t.rhs == (a, b, c, a&b, a&c, b&c, a&b&c)
    @test issetequal(terms(t), (y, a, b, c))

    ## Interactions with `1` reduce to main effect.
    t = @formula(y ~ 1 & x1)
    @test t.rhs == x1

    t = @formula(y ~ (1 + x1) & x2)
    @test t.rhs == (x2, x1&x2)

    ## PR #54 breaks formula-level equality because original (un-lowered)
    ## expression is kept on Formula struct.  but functional (RHS) equality
    ## should be maintained
    using StatsModels: drop_term

    @test drop_term(@formula(foo ~ 1 + bar + baz), term(:bar)) ==
        @formula(foo ~ 1 + baz)
    @test drop_term(@formula(foo ~ 1 + bar + baz), term(1)) ==
        @formula(foo ~ bar + baz)

    # drop_term no longer checks for whether term is found...
    @test_broken drop_term(@formula(foo ~ bar + baz), term(0))
    @test_broken drop_term(@formula(foo ~ bar + baz), term(:boz))

    form = @formula(foo ~ 1 + bar + baz)
    @test form == @formula(foo ~ 1 + bar + baz)
    @test drop_term(form, term(:bar)) == @formula(foo ~ 1 + baz)
    # drop_term creates a new formula:
    @test form != @formula(foo ~ 1 + baz)

    # Incorrect formula separator
    @test_throws LoadError @eval @formula(y => x + 1)

    # copying formulas
    f = @formula(foo ~ 1 + bar)
    @test f == deepcopy(f)

    f = @formula(foo ~ bar)
    @test f == deepcopy(f)

end
