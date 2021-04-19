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
        # unprotect reverts to treating calls to +, &, and * as term union,
        # interaction, and combined

        f = @formula(0 ~ 1 - unprotect(a&b))
        ff = apply_schema(f, schema(d))
        @test modelcols(ff.rhs, d) ≈ 1 .- d.a .* d.b

        # ideally you'd also be able to do these but it's hard to make it work...
        # this fails because - doesn't auto-broadcast, and the broadcasting that
        # happens during FunctionTerm evaluation gets used up by the (a,b) tuple.
        ff = apply_schema(@formula(0 ~ 1 - unprotect(a+b)), schema(d))
        @test_broken modelcols(ff.rhs, d) == 1 .- [d.a d.b]

        # and even if we define a broadcasting version, still fails because of
        # packing the result into a right-sized container.  end up with a tuple
        # of arrays which needs to be collected into a matrix
        my_sub = (x,y) -> x .- y
        ff = apply_schema(@formula(0 ~ my_sub(1, unprotect(a+b))), schema(d))
        @test_broken modelcols(ff.rhs, d) == 1 .- [d.a d.b]
        
        # both of these could be fixed by always returning a matrix when you call
        # modelcols on a tuple of terms but that would break other things
    end

end
