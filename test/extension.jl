using StatsModels: collect_matrix_terms, MatrixTerm, AbstractTerm

struct NotAllowedToCallError <: Exception
    msg::String
end
poly(x, n) = throw(NotAllowedToCallError("poly function should be only used in a @formula"))

abstract type PolyModel end
struct PolyTerm{T<:AbstractTerm} <: AbstractTerm
    term::T
    deg::Int
end

function StatsModels.apply_schema(t::CallTerm{typeof(poly)}, sch, Mod::Type{<:PolyModel})
    parsed_term, parsed_deg = t.args_parsed
    term = apply_schema(parsed_term, sch, Mod)
    deg = unprotect(parsed_deg).n
    PolyTerm(term, deg)
end

function StatsModels.modelcols(p::PolyTerm, d::NamedTuple)
    term_col = modelcols(p.term, d)
    reduce(hcat, [term_col.^n for n in 1:p.deg])
end

struct NonMatrixTerm{T} <: AbstractTerm
    term::T
end

StatsModels.is_matrix_term(::Type{<:NonMatrixTerm}) = false
StatsModels.apply_schema(t::NonMatrixTerm, sch, Mod::Type) =
    NonMatrixTerm(apply_schema(t.term, sch, Mod))
StatsModels.modelcols(t::NonMatrixTerm, d) = modelcols(t.term, d)

@testset "Extended formula/models" begin
    d = (z = rand(10), y = rand(10), x = collect(1:10))
    sch = schema(d)

    @testset "Poly term" begin
        f = @formula(y ~ poly(x, protect(3)))

        f_plain = apply_schema(f, sch)
        @test f_plain.rhs.terms[1] isa FunctionCallTerm
        @test_broken f_plain == apply_schema(f, sch, Nothing)
        # Default behavour when evaluated as a function is to error
        @test_throws NotAllowedToCallError modelcols(f_plain, d) == hcat(d[:x].^3)

        f_special = apply_schema(f, sch, PolyModel)
        @test f_special.rhs.terms[1] isa PolyTerm
        @test last(modelcols(f_special, d)) == hcat(d[:x], d[:x].^2, d[:x].^3)
    end

    @testset "nesting of functional terms and custom terms" begin
        @testset "Custom functional term used inside a normal function" begin
            f = @formula(y ~ max(x, poly(x, 1)))
            f_special = apply_schema(f, sch, PolyModel)
            @test last(modelcols(f_special, d)) |> vec == 1:10
        end

        @testset "Custom functional term used inside a custom functional term" begin
            f = @formula(y ~ poly(poly(x,1), 1))
            f_special = apply_schema(f, sch, PolyModel)
            @test last(modelcols(f_special, d)) |> vec == 1:10
        end

        @testset "Normal functional term used inside a custom functional term" begin
            f = @formula(y ~ poly(max(x, x), 1))
            f_special = apply_schema(f, sch, PolyModel)
            @test last(modelcols(f_special, d)) |> vec == 1:10
        end

        @testset "Normal functional term used inside a normal functional term" begin
            f = @formula(y ~ max(x, max(x, x)))
            f_special = apply_schema(f, sch, PolyModel)
            @test last(modelcols(f_special, d)) |> vec == 1:10
        end
    end


    @testset "Non-matrix term" begin
        f = @formula(z ~ x + y)
        f2 = term(:z) ~ term(:x) + NonMatrixTerm(term(:y))
        f3 = term(:z) ~ NonMatrixTerm(term(:x)) + term(:y)
        f4 = term(:z) ~ NonMatrixTerm.(f.rhs)
        f5 = term(:z) ~ term(:x) + NonMatrixTerm(term(:y)) + term(:y)

        @test collect_matrix_terms(f.rhs) == MatrixTerm((term(:x) + term(:y)))
        @test collect_matrix_terms(f2.rhs) ==
            (MatrixTerm((term(:x), )), NonMatrixTerm(term(:y)))
        @test collect_matrix_terms(f3.rhs) ==
            (MatrixTerm((term(:y), )), NonMatrixTerm(term(:x)))
        @test collect_matrix_terms(f4.rhs) == f4.rhs
        @test collect_matrix_terms(f5.rhs) ==
            (MatrixTerm((term(:x), term(:y))), NonMatrixTerm(term(:y)))

        f = apply_schema(f, sch)
        @test f.rhs isa MatrixTerm
        @test f.rhs == collect_matrix_terms(f.rhs)
        @test modelcols(f.rhs, d) == hcat(d.x, d.y)

        f2 = apply_schema(f2, sch)
        @test f2.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f2.rhs == apply_schema((MatrixTerm(term(:x)), NonMatrixTerm(term(:y))), sch)
        @test modelcols(f2.rhs, d) == (hcat(d.x), d.y)

        # matrix term goes first
        f3 = apply_schema(f3, sch)
        @test f3.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f3.rhs == apply_schema((MatrixTerm(term(:y)), NonMatrixTerm(term(:x))), sch)
        @test modelcols(f3.rhs, d) == (hcat(d.y), d.x)

        f4 = apply_schema(f4, sch)
        @test f4.rhs isa Tuple{NonMatrixTerm, NonMatrixTerm}
        @test f4.rhs == apply_schema((NonMatrixTerm(term(:x)), NonMatrixTerm(term(:y))), sch)
        @test modelcols(f4.rhs, d) == (d.x, d.y)

        # matrix terms are gathered
        f5 = apply_schema(f5, sch)
        @test f5.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f5.rhs ==
            apply_schema((MatrixTerm((term.((:x, :y)))), NonMatrixTerm(term(:y))), sch)
        @test modelcols(f5.rhs, d) == (hcat(d.x, d.y), d.y)

    end

end
