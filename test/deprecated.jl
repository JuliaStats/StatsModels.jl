@testset "Deprecations" begin
    f = @formula y ~ 1 + a*b

    f2 = @test_warn "deprecated" Formula(f.lhs, f.rhs)
    @test f2.lhs == f.lhs
    @test f2.rhs == f.rhs
    @test f2.ex == f.ex
    @test f2.ex_orig == :()

    f3 = @eval @formula $(f.lhs) ~ $(f.rhs)
    @test f3.lhs == f.lhs
    @test f3.rhs == f.rhs
    @test f3.ex == f.ex
    @test f3.ex_orig == f.ex
    @test f3.ex_orig != f.ex_orig
end
