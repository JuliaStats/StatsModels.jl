@testset "formula" begin

    y, x1, x2, x3, a, b, c, onet = term.((:y, :x1, :x2, :x3, :a, :b, :c, 1))

    ## totally empty
    t = @formula(0 ~ 0)
    @test !hasresponse(t)
    @test !hasintercept(t)
    @test omitsintercept(t)
    @test t.rhs == ConstantTerm(0)
    @test issetequal(terms(t), [ConstantTerm(0)])

    ## empty lhs, intercept on rhs
    t = @formula(0 ~ 1)
    @test !hasresponse(t)
    @test hasintercept(t)
    @test !omitsintercept(t)

    ## empty RHS
    t = @formula(y ~ 0)
    @test hasintercept(t) == false
    @test omitsintercept(t) == true
    @test hasresponse(t)
    @test t.rhs == ConstantTerm(0)
    @test issetequal(terms(t), term.((:y, 0)))

    t = @formula(y ~ -1)
    @test hasintercept(t) == false
    @test omitsintercept(t) == true

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
    @test omitsintercept(t) == false
    @test t.rhs == (x1, x2)
    @test issetequal(terms(t), [y, x1, x2])

    ## no intercept
    t = @formula(y ~ 0 + x1 + x2)
    @test hasintercept(t) == false
    @test omitsintercept(t) == true
    @test t.rhs == term.((0, :x1, :x2))

    t = @formula(y ~ -1 + x1 + x2)
    @test hasintercept(t) == false
    @test omitsintercept(t) == true
    @test t.rhs == term.((-1, :x1, :x2))

    t = @formula(y ~ x1 & x2)
    @test hasintercept(t) == false
    @test omitsintercept(t) == false
    @test t.rhs == x1&x2
    @test issetequal(terms(t), [y, x1, x2])

    ## `*` expansion
    t = @formula(y ~ x1 * x2)
    @test hasintercept(t) == false
    @test omitsintercept(t) == false
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
    f = @formula(foo ~ bar + baz)
    @test drop_term(f, term(0)) == f
    @test drop_term(f, term(:boz)) == f

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

    # Keyword arguments in function calls
    @testset "function call kwargs" begin
        myf(args...; kwargs...) = sum(args)

        # Semicolon kwargs syntax
        f = @formula(y ~ myf(x; k=10, bs=:cr))
        ft = f.rhs
        @test ft isa FunctionTerm
        @test has_kwargs(ft)
        kws = kwarg_exprs(ft)
        @test length(kws) == 2
        @test kws[1].args[1] == :k
        @test kws[1].args[2] == 10
        @test kws[2].args[1] == :bs

        # Comma kwargs syntax
        f2 = @formula(y ~ myf(x, k=10, bs=:cr))
        @test has_kwargs(f2.rhs)
        @test length(kwarg_exprs(f2.rhs)) == 2

        # No kwargs — backward compat
        f3 = @formula(y ~ myf(x, 10))
        @test !has_kwargs(f3.rhs)
        @test isempty(kwarg_exprs(f3.rhs))

        # Mixed positional + kwargs
        f4 = @formula(y ~ myf(x, 10; bs=:cr))
        @test has_kwargs(f4.rhs)
        kws4 = kwarg_exprs(f4.rhs)
        @test length(kws4) == 1
        @test kws4[1].args[1] == :bs

        # Multiple terms, some with kwargs
        f5 = @formula(y ~ myf(x; k=10) + log(z) + w)
        for t in f5.rhs
            if t isa FunctionTerm && t.f === myf
                @test has_kwargs(t)
            elseif t isa FunctionTerm && t.f === log
                @test !has_kwargs(t)
            end
        end

        # Standard formulas still work
        f6 = @formula(y ~ 1 + x * z)
        @test f6 isa FormulaTerm
    end

end
