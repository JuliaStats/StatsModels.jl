using StatsModels: extract_matrix_terms, MatrixTerm

poly(x, n) = x^n

abstract type PolyModel end
struct PolyTerm <: AbstractTerm
    term::Symbol
    deg::Int
end
PolyTerm(t::Term, deg::ConstantTerm) = PolyTerm(t.sym, deg.n)

StatsModels.apply_schema(t::FunctionTerm{typeof(poly)}, sch, ::Type{PolyModel}) =
    PolyTerm(t.args_parsed...)

StatsModels.model_cols(p::PolyTerm, d::NamedTuple) =
    reduce(hcat, (d[p.term].^n for n in 1:p.deg))

struct NonMatrixTerm{T} <: AbstractTerm
    term::T
end

StatsModels.is_matrix_term(::Type{NonMatrixTerm{T}}) where T = false
StatsModels.apply_schema(t::NonMatrixTerm, sch, Mod) =
    NonMatrixTerm(apply_schema(t.term, sch, Mod))
StatsModels.model_cols(t::NonMatrixTerm, d) = model_cols(t.term, d)

@testset "Extended formula/models" begin
    d = (z = rand(10), y = rand(10), x = collect(1:10))
    sch = schema(d)

    @testset "Poly term" begin
        f = @formula(y ~ poly(x, 3))

        f_plain = apply_schema(f, sch)
        @test f_plain.rhs.terms[1] isa FunctionTerm
        @test f_plain == apply_schema(f, sch, Nothing)
        @test last(model_cols(f_plain, d)) == d[:x].^3
        
        f_special = apply_schema(f, sch, PolyModel)
        @test f_special.rhs.terms[1] isa PolyTerm
        @test last(model_cols(f_special, d)) == hcat(d[:x], d[:x].^2, d[:x].^3)
    end
    
    @testset "Non-matrix term" begin
        f = @formula(z ~ x + y)
        f2 = term(:z) ~ term(:x) + NonMatrixTerm(term(:y))
        f3 = term(:z) ~ NonMatrixTerm(term(:x)) + term(:y)
        f4 = term(:z) ~ NonMatrixTerm.(f.rhs)
        f5 = term(:z) ~ term(:x) + NonMatrixTerm(term(:y)) + term(:y)

        @test extract_matrix_terms(f.rhs) == MatrixTerm((term(:x) + term(:y)))
        @test extract_matrix_terms(f2.rhs) ==
            (MatrixTerm((term(:x), )), NonMatrixTerm(term(:y)))
        @test extract_matrix_terms(f3.rhs) ==
            (MatrixTerm((term(:y), )), NonMatrixTerm(term(:x)))
        @test extract_matrix_terms(f4.rhs) == f4.rhs
        @test extract_matrix_terms(f5.rhs) ==
            (MatrixTerm((term(:x), term(:y))), NonMatrixTerm(term(:y)))

        f = apply_schema(f, sch)
        @test f.rhs isa MatrixTerm
        @test f.rhs == extract_matrix_terms(f.rhs)
        @test model_cols(f.rhs, d) == hcat(d.x, d.y)

        f2 = apply_schema(f2, sch)
        @test f2.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f2.rhs == apply_schema((MatrixTerm(term(:x)), NonMatrixTerm(term(:y))), sch)
        @test model_cols(f2.rhs, d) == (d.x, d.y)

        # matrix term goes first
        f3 = apply_schema(f3, sch)
        @test f3.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f3.rhs == apply_schema((MatrixTerm(term(:y)), NonMatrixTerm(term(:x))), sch)
        @test model_cols(f3.rhs, d) == (d.y, d.x)

        f4 = apply_schema(f4, sch)
        @test f4.rhs isa Tuple{NonMatrixTerm, NonMatrixTerm}
        @test f4.rhs == apply_schema((NonMatrixTerm(term(:x)), NonMatrixTerm(term(:y))), sch)
        @test model_cols(f4.rhs, d) == (d.x, d.y)

        # matrix terms are gathered
        f5 = apply_schema(f5, sch)
        @test f5.rhs isa Tuple{MatrixTerm, NonMatrixTerm}
        @test f5.rhs ==
            apply_schema((MatrixTerm((term(:x, :y))), NonMatrixTerm(term(:y))), sch)
        @test model_cols(f5.rhs, d) == (hcat(d.x, d.y), d.y)
        
    end

end

