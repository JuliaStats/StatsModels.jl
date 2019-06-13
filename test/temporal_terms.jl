using StatsModels
using StatsBase
using StatsModels: width
using DataStructures

@testset "Temporal Terms" begin
    @testset "Basic use" begin
        df = (y=1:10, x = 1:10)
        f = @formula(y ~ lag(x, 0) + lag(x, 1) + lag(x, 3) + lag(x, 11))
        f = apply_schema(f, schema(f, df))
        resp, pred = modelcols(f, df)

        @test isequal(pred[:, 1], 1.0:10)
        @test isequal(pred[:, 2], [missing; 1.0:9])
        @test isequal(pred[:, 3], [missing; missing; missing; 1.0:7])
        @test isequal(pred[:, 4], fill(missing, 10))

        @test coefnames(f)[2] == ["x_lag0", "x_lag1", "x_lag3", "x_lag11"]
    end

    @testset "1 arg form" begin
        df = (y=1:10, x = 1:10)
        f = @formula(y ~ lag(x))
        f = apply_schema(f, schema(f, df))
        resp, pred = modelcols(f, df)

        @test isequal(pred[:, 1], [missing; 1.0:9])
        @test coefnames(f)[2] == "x_lag1"
    end

    @testset "Nested Use" begin
        df = (y=1:10, x = 1:10)
        f = @formula(y ~ lag(lag(x, 1), 2))  # equiv to `lag(x, 3)`
        f = apply_schema(f, schema(f, df))
        resp, pred = modelcols(f, df);

        @test isequal(pred[:, 1], [missing; missing; missing; 1.0:7])
    end

    @testset "Unhappy path" begin
        @testset "Negative lag" begin
            df = (y=1:10, x = 1:10)
            lead_f = @formula(y ~ lag(x, -20))
            lead_f = apply_schema(lead_f, schema(lead_f, df))

            # This is an ErrorException and not a ArgumentError because:
            # https://github.com/JuliaLang/julia/issues/32307
            @test_throws ErrorException modelcols(lead_f, df);
        end

        @testset "Variable lag" begin
            df = (y=1:5, x = 1:5, offset=[0, 1, 0, 2, 1])
            bad_f = @formula(y ~ lag(x, offset))
            @test_throws ArgumentError apply_schema(bad_f, schema(bad_f, df))

        end

        @testset "Fractional lag" begin
            df = (y=1:10, x = 1:10)
            bad_f = @formula(y ~ lag(x, 1.5))
            @test_throws MethodError apply_schema(bad_f, schema(bad_f, df))
        end
    end
end
