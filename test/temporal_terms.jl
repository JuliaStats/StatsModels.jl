using StatsModels
using StatsBase
using StatsModels: width
using DataStructures

@testset "Temporal Terms" begin
    df = (y=1:10, x = 1:10)
    f = @formula(y ~ lag(x, 0) + lag(x, 1) + lag(x, 3) + lag(x, 11))
    f = apply_schema(f, schema(f, df))
    resp, pred = modelcols(f, df);

    @test pred[1, :] = 1:10
    @test pred[2, :] = [missing; 1:9]
    @test pred[3, :] = [missing; missing; missing; 1:7]
    @test pred[4, :] = fill(10, missing)

    @test coefnames(f)[2] = ["x_lagged_by_0", "x_lagged_by_1", "x_lagged_by_3", "x_lagged_by_11"])

    # Negative lag is not permitted (at least for now)
    lead_f = @formula(y ~ lag(x, -20))
    lead_f = apply_schema(lead_f, schema(lead_f, df))
    @test_throws ArgumentError modelcols(lead_f, df);
end
