@testset "Deprecations" begin
    f = @formula y ~ 1 + a*b

    if VERSION > v"0.7.0-DEV"
        testex = :(@test_logs (:warn, r"Formula\(lhs, rhs\) is deprecated") Formula($f.lhs, $f.rhs))
    else
        testex = :(@test_warn "deprecated" Formula($f.lhs, $f.rhs))
    end
    f2 = eval(testex)
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
