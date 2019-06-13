using StatsModels
using StatsBase
using StatsModels: width
using DataStructures

@testset "Temporal Terms" begin
    @testset "Lag" begin
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

        @testset "Negative lag" begin
            df = (y=1:10, x = 1:10)
            neg_f = @formula(y ~ lag(x, -2))
            neg_f = apply_schema(neg_f, schema(neg_f, df))
            resp, pred = modelcols(neg_f, df);

            @test isequal(pred[:, 1], [3.0:10; missing; missing])
            @test coefnames(neg_f)[2] == "x_lag-2"
        end

        @testset "Diff Demo" begin
            df = (y=1:10, x = 1:10)
            f = @formula(y ~ (x - lag(x)))
            f = apply_schema(f, schema(f, df))
            # Broken because of: https://github.com/JuliaStats/StatsModels.jl/issues/114
            @test_broken resp, pred = modelcols(f, df);
            @test_broken isequal(pred[:, 1], [missing; fill(1, 9)])
        end

        @testset "Unhappy path" begin
            @testset "Variable lag" begin
                df = (y=1:5, x = 1:5, offset=[0, 1, 0, 2, 1])
                bad_f = @formula(y ~ lag(x, offset))
                @test_throws ArgumentError apply_schema(bad_f, schema(bad_f, df))
            end

            @testset "Fractional lag" begin
                df = (y=1:10, x = 1:10)
                bad_f = @formula(y ~ lag(x, 1.5))
                @test_throws InexactError apply_schema(bad_f, schema(bad_f, df))
            end
        end
    end # Lag testset

    # The code for lag and lead is basically the same, as we tested lag comprehensively above
    # the tests for lead are more sparse.
    @testset "Lead" begin
        @testset "Basic use" begin
            df = (y=1:10, x = 1:10)
            f = @formula(y ~ lead(x, 0) + lead(x, 1) + lead(x, 3) + lead(x, 11))
            f = apply_schema(f, schema(f, df))
            resp, pred = modelcols(f, df)

            @test isequal(pred[:, 1], 1.0:10)
            @test isequal(pred[:, 2], [2.0:10; missing])
            @test isequal(pred[:, 3], [4.0:10; missing; missing; missing])
            @test isequal(pred[:, 4], fill(missing, 10))

            @test coefnames(f)[2] == ["x_lead0", "x_lead1", "x_lead3", "x_lead11"]
        end
    end
end
