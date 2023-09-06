using StatsAPI: RegressionModel

struct MyRegressionModel <: RegressionModel
end

StatsAPI.modelmatrix(::MyRegressionModel) = [1 2; 3 4]
StatsAPI.vcov(::MyRegressionModel) = [1 0; 0 1]

struct MyRegressionModel2 <: RegressionModel
end

StatsAPI.modelmatrix(::MyRegressionModel2) = [1 2; 1 2]
StatsAPI.vcov(::MyRegressionModel2) = [1 0; 0 1]

struct MyRegressionModel3 <: RegressionModel
end

StatsAPI.modelmatrix(::MyRegressionModel3) = [1 2 3; 1 2 3]
StatsAPI.vcov(::MyRegressionModel3) = [1 0 0; 0 1 0; 0 0 1]

@testset "VIF" begin
    # no intercept term
    @test_throws ArgumentError vif(MyRegressionModel())

    # only one non intercept term
    @test_throws ArgumentError vif(MyRegressionModel2())

    # vcov is identity, so the VIF is just 1
    @test vif(MyRegressionModel3()) ≈ [1, 1]
end
