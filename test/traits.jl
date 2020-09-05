using StatsModels: hasintercept, omitsintercept
import StatsModels: drop_intercept, implicit_intercept

struct DroppyMod <: StatisticalModel end
drop_intercept(::Type{DroppyMod}) = true

# define structs for testing implicit intercept trait:

# default for StatisticalModel is true
struct DefaultImplicit <: StatisticalModel end

# override default = true for StatisticalModels
struct NoImplicit <: StatisticalModel end
implicit_intercept(::Type{NoImplicit}) = false

# manual override of default = false
struct YesImplicit end
implicit_intercept(::Type{YesImplicit}) = true


@testset "Model traits" begin
    d = (y = rand(10), x = rand(10), z = [:a, :b, :c])
    sch = schema(d)
    f = @formula(y ~ x)
    f1 = @formula(y ~ 1 + x)
    f0 = @formula(y ~ 0 + x)

    @testset "drop_intercept" begin
        @test_throws ArgumentError apply_schema(f1, sch, DroppyMod)
        ff = apply_schema(f, sch, DroppyMod)
        @test !hasintercept(ff)
        @test !omitsintercept(ff)
        ff0 = apply_schema(f0, sch, DroppyMod)
        @test !hasintercept(ff0)
        @test omitsintercept(ff0)

        @test drop_intercept(DroppyMod()) == drop_intercept(DroppyMod)
        # drop_intercept blocks implicit_intercept == true
        @test implicit_intercept(DroppyMod) == true

        @testset "categorical promotion" begin 
            # drop_intercept == true means that model should always ACT like
            # intercept is present even if it's not specified or even ommitted.
            # (pushes intercept term to the FullRank already seen terms list).

            # full dummy coding
            @test width(apply_schema(@formula(y ~ 0 + z), sch, StatisticalModel).rhs) == 3
            # droppy regular coding
            @test width(apply_schema(@formula(y ~ 0 + z), sch, DroppyMod).rhs) == 2
        end
    end

    @testset "implicit_intercept" begin
        @testset "default" begin
            ff, ff0, ff1 = apply_schema.((f, f0, f1), Ref(sch), Any)
            @test !hasintercept(ff)
            @test !hasintercept(ff0)
            @test hasintercept(ff1)
            @test !omitsintercept(ff)
            @test omitsintercept(ff0)
            @test !omitsintercept(ff1)
        end

        @testset "StatisticalModel default" begin
            ff, ff0, ff1 = apply_schema.((f, f0, f1), Ref(sch), DefaultImplicit)
            @test hasintercept(ff)
            @test !hasintercept(ff0)
            @test hasintercept(ff1)
            @test !omitsintercept(ff)
            @test omitsintercept(ff0)
            @test !omitsintercept(ff1)

            @test implicit_intercept(DefaultImplicit()) == implicit_intercept(DefaultImplicit)
        end

        @testset "Override StatisticalModel default" begin
            ff, ff0, ff1 = apply_schema.((f, f0, f1), Ref(sch), NoImplicit)
            @test !hasintercept(ff)
            @test !hasintercept(ff0)
            @test hasintercept(ff1)
            @test !omitsintercept(ff)
            @test omitsintercept(ff0)
            @test !omitsintercept(ff1)

            @test implicit_intercept(NoImplicit()) == implicit_intercept(NoImplicit)
        end

        @testset "Override Any default" begin
            ff, ff0, ff1 = apply_schema.((f, f0, f1), Ref(sch), YesImplicit)
            # broken because traits are not checked during apply_schema for
            # context that is not <:StatisticalModel
            @test_broken hasintercept(ff)
            @test !hasintercept(ff0)
            @test hasintercept(ff1)
            @test !omitsintercept(ff)
            @test omitsintercept(ff0)
            @test !omitsintercept(ff1)

            @test implicit_intercept(YesImplicit()) == implicit_intercept(YesImplicit)
        end
        
    end
end
