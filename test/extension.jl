poly(x, n) = x^n

abstract type PolyModel end
struct PolyTerm
    term::Symbol
    deg::Int
end
PolyTerm(t::Term, deg::ConstantTerm) = PolyTerm(t.sym, deg.n)

StatsModels.apply_schema(t::FunctionTerm{typeof(poly)}, sch, ::Type{PolyModel}) =
    PolyTerm(t.args_parsed...)

StatsModels.model_cols(p::PolyTerm, d::NamedTuple) =
    reduce(hcat, (d[p.term].^n for n in 1:p.deg))


@testset "Extended formula/models" begin
    
    d = (y = rand(10), x = collect(1:10))
    sch = schema(d)
    f = @formula(y ~ poly(x, 3))

    f_plain = apply_schema(f, sch)
    @test f_plain.rhs isa FunctionTerm
    @test f_plain == apply_schema(f, sch, Nothing)
    @test last(model_cols(f_plain, d)) == d[:x].^3
    
    f_special = apply_schema(f, sch, PolyModel)
    @test f_special.rhs isa PolyTerm
    @test last(model_cols(f_special, d)) == hcat(d[:x], d[:x].^2, d[:x].^3)

end
