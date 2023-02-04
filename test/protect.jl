@testset "Protection" begin
    d = (a=rand(10), b=[1:10;], c=rand(Int, 10))

    @testset "protect" begin
        # protect blocks interpreting +, &, and * as formula specials
        f = @formula(0 ~ protect(a+b) + a + b)
        ff = apply_schema(f, schema(d))
        @test ff.rhs.terms[1] isa FunctionTerm{typeof(+)}
        @test modelcols(ff.rhs, d) == [d.a .+ d.b d.a d.b]

        # protect is applied by default inside FunctionTerm args
        f = @formula(0 ~ 1 - protect(a+b))
        ff = apply_schema(f, schema(d))
        ff2 = apply_schema(@formula(0 ~ 1 - (a+b)), schema(d))
        @test modelcols(ff.rhs, d) == modelcols(ff2.rhs, d) ≈ 1 .- (d.a .+ d.b)
    end

    @testset "unprotect" begin
        using StatsModels: TupleTerm, FullRank
        # unprotect reverts to treating calls to +, &, and * as term union,
        # interaction, and combined

        # helper to "lift" function into FunctionTerm constructor
        function ft(f)
            return function(args...)
                return FunctionTerm(f, args, :($f($(args...))))
            end
        end

        sch = schema(d)
        a, b, c = apply_schema.(term.((:a, :b, :c)), Ref(sch))

        ops_types = ((+) => TupleTerm,
                     (&) => InteractionTerm,
                     (*) => TupleTerm,
                     (~) => FormulaTerm)

        for (op, typ) in ops_types, sch in (sch, FullRank(sch))
            f = ft(op)(a, b)
            @test f isa FunctionTerm{typeof(op)}
            ff = apply_schema(f, sch)
            @test ff isa typ
            op != (~) && @test ff == op(a, b)
        end

        # make sure it's recursively applied
        f = ft(*)(ft(+)(a, b), c)
        @test apply_schema(f, sch) == (a + b) * c

        # stops once it hits an non-special call still
        f = ft(+)(a, ft(log)(ft(+)(term(1), b)))
        @test apply_schema(f, sch) == (a, f.args[2])

        # testing behavior of modelcols
        f = @formula(0 ~ 1 - unprotect(a&b))
        ff = apply_schema(f, schema(d))
        @test modelcols(ff.rhs, d) ≈ 1 .- d.a .* d.b

        # ideally you'd also be able to do these but it's hard to make it work...
        # this fails because - doesn't auto-broadcast, and the broadcasting that
        # happens during FunctionTerm evaluation gets used up by the (a,b) tuple.
        f = @formula(0 ~ 1 - unprotect(a+b))
        @test f.rhs.args[end] isa FunctionTerm{typeof(unprotect)}
        ff = apply_schema(f, schema(d))
        @test ff.rhs.terms[1].args[end] isa StatsModels.TupleTerm
        @test_broken modelcols(ff.rhs, d) == 1 .- [d.a d.b]

        # and even if we define a broadcasting version, still fails because it
        # gives a tuple of arrays instead of a matrix
        my_sub = (x,y) -> x .- y
        ff = apply_schema(@formula(0 ~ my_sub(1, unprotect(a+b))), schema(d))
        @test_broken modelcols(ff.rhs, d) == 1 .- [d.a d.b]
        
        # both of these could be fixed by always returning a matrix when you call
        # modelcols on a tuple of terms but that would break other things
    end

end
