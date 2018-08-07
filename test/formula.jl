@testset "formula" begin

    # TODO:
    # - grouped variables in formulas with interactions
    # - is it fast?  Can expand() handle DataFrames?
    # - deal with intercepts
    # - implement ^2 for datavector's
    # - support more transformations with I()?

    ## Formula parsing
    using StatsModels: @formula, Formula, Terms

    ## totally empty
    t = Terms(@eval @formula $(:($nothing ~ 0)))
    @test t.response == false
    @test t.intercept == false
    @test t.terms == []
    @test t.eterms == []

    ## empty RHS
    t = Terms(@formula(y ~ 0))
    @test t.intercept == false
    @test t.terms == []
    @test t.eterms == [:y]
    t = Terms(@formula(y ~ -1))
    @test t.intercept == false
    @test t.terms == []

    ## intercept-only
    t = Terms(@formula(y ~ 1))
    @test t.response == true
    @test t.intercept == true
    @test t.terms == []
    @test t.eterms == [:y]

    ## terms add
    t = Terms(@formula(y ~ 1 + x1 + x2))
    @test t.intercept == true
    @test t.terms == [:x1, :x2]
    @test t.eterms == [:y, :x1, :x2]

    ## implicit intercept behavior:
    t = Terms(@formula(y ~ x1 + x2))
    @test t.intercept == true
    @test t.terms == [:x1, :x2]
    @test t.eterms == [:y, :x1, :x2]

    ## no intercept
    t = Terms(@formula(y ~ 0 + x1 + x2))
    @test t.intercept == false
    @test t.terms == [:x1, :x2]

    @test t ==
        Terms(@formula(y ~ -1 + x1 + x2)) ==
        Terms(@formula(y ~ x1 - 1 + x2)) ==
        Terms(@formula(y ~ x1 + x2 -1))

    ## can't subtract terms other than 1
    ## (this does error but @test_throws doesn't catch it somehow...)
    # @test_throws LoadError Terms(@formula(y ~ x1 - x2)) 

    t = Terms(@formula(y ~ x1 & x2))
    @test t.terms == [:(x1 & x2)]
    @test t.eterms == [:y, :x1, :x2]

    ## `*` expansion
    t = Terms(@formula(y ~ x1 * x2))
    @test t.terms == [:x1, :x2, :(x1 & x2)]
    @test t.eterms == [:y, :x1, :x2]

    ## associative rule:
    ## +
    t = Terms(@formula(y ~ x1 + x2 + x3))
    @test t.terms == [:x1, :x2, :x3]

    ## &
    t = Terms(@formula(y ~ x1 & x2 & x3))
    @test t.terms == [:((&)(x1, x2, x3))]
    @test t.eterms == [:y, :x1, :x2, :x3]

    ## distributive property of + and &
    t = Terms(@formula(y ~ x1 & (x2 + x3)))
    @test t.terms == [:(x1&x2), :(x1&x3)]

    ## ordering of interaction terms is preserved across distributive
    t = Terms(@formula(y ~ (x2 + x3) & x1))
    @test t.terms == [:(x2&x1), :(x3&x1)]

    ## distributive with *
    t = Terms(@formula(y ~ (a + b) * c))
    @test t.terms == [:a, :b, :c, :(a&c), :(b&c)]

    ## three-way *
    t = Terms(@formula(y ~ x1 * x2 * x3))
    @test t.terms == [:x1, :x2, :x3,
                      :(x1&x2), :(x1&x3), :(x2&x3),
                      :((&)(x1, x2, x3))]
    @test t.eterms == [:y, :x1, :x2, :x3]

    ## Interactions with `1` reduce to main effect.
    t = Terms(@formula(y ~ 1 & x1))
    @test t.terms == [:x1]

    t = Terms(@formula(y ~ (1 + x1) & x2))
    @test t.terms == [:x2, :(x1&x2)]

    ## PR #54 breaks formula-level equality because original (un-lowered)
    ## expression is kept on Formula struct.  but functional (RHS) equality
    ## should be maintained
    using StatsModels: dropterm!

    @test Terms(dropterm(@formula(foo ~ 1 + bar + baz), :bar)) ==
        Terms(@formula(foo ~ 1 + baz))
    @test Terms(dropterm(@formula(foo ~ 1 + bar + baz), 1)) ==
        Terms(@formula(foo ~ 0 + bar + baz))

    @test_throws ArgumentError dropterm(@formula(foo ~ 0 + bar + baz), 0)
    @test_throws ArgumentError dropterm(@formula(foo ~ 0 + bar + baz), :boz)

    form = @formula(foo ~ 1 + bar + baz)
    @test form == @formula(foo ~ 1 + bar + baz)
    @test Terms(dropterm!(form, :bar)) == Terms(@formula(foo ~ 1 + baz))
    @test Terms(form) == Terms(@formula(foo ~ 1 + baz))

    # Incorrect formula separator
    # does error, not caught by @test_throws
    # @test_throws ArgumentError @formula(y => x + 1)

    # copying formulas
    f = @formula(foo ~ 1 + bar)
    @test f == copy(f)

    f = @formula(foo ~ bar)
    @test f == copy(f)

end
