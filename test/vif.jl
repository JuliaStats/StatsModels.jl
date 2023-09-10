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

Base.@kwdef struct Duncan <: RegressionModel
    coefnames::Vector{String}
    coef::Vector{Float64}
    stderror::Vector{Float64}
    modelmatrix::Matrix{Float64}
    vcov::Matrix{Float64}
    formula::FormulaTerm
end

for f in [:coefnames, :coef, :stderror, :modelmatrix, :vcov]
    @eval StatsAPI.$f(model::Duncan) = model.$f
end 

StatsModels.formula(model::Duncan) = model.formula

@testset "VIF input checks" begin
    # no intercept term
    @test_throws ArgumentError vif(MyRegressionModel())

    # only one non intercept term
    @test_throws ArgumentError vif(MyRegressionModel2())

    # vcov is identity, so the VIF is just 1
    @test vif(MyRegressionModel3()) ≈ [1, 1]
end

@testset "GVIF and VIF are the same for continuous predictors" begin
    # these are copied from a GLM fit to the car::duncan data 
    duncan2 = Duncan(; coefnames=["(Intercept)", "Income", "Education"],
                     formula=term(:Prestige) ~  InterceptTerm{true}() + ContinuousTerm(:Income, 1,1,1,1) + 
                                                ContinuousTerm(:Education, 1,1,1,1),
                     coef=[-6.064662922103356, 0.5987328215294941, 0.5458339094008812], 
                     stderror=[4.271941174529124, 0.11966734981235407, 0.0982526413303999],
                     # we actually don't need the whole matrix -- just enough to find an intercept
                     modelmatrix=[1.0 62.0 86.0], 
                     vcov=[18.2495    -0.151845    -0.150706
                           -0.151845   0.0143203   -0.00851855
                           -0.150706  -0.00851855   0.00965358])
    @test vif(duncan2) ≈ [2.1049, 2.1049] atol=1e-5
    # two different ways of calculating the same quantity
    @test vif(duncan2) ≈ gvif(duncan2) 
end

@testset "GVIF" begin
    cm = StatsModels.ContrastsMatrix(DummyCoding("bc", ["bc", "prof", "wc"]), ["bc", "prof", "wc"])
    duncan3 = Duncan(; coefnames=["(Intercept)", "Income", "Education",  "Type: prof", "Type: wc"],
                     formula=term(:Prestige) ~  InterceptTerm{true}() + ContinuousTerm(:Income, 1,1,1,1) + 
                                                ContinuousTerm(:Education, 1,1,1,1) + CategoricalTerm(:Type, cm),
                     coef=[0.185028, 0.597546, 0.345319, 16.6575, -14.6611], 
                     stderror=[3.71377, 0.0893553, 0.113609, 6.99301, 6.10877],
                     # we actually don't need the whole matrix -- just enough to find an intercept
                     modelmatrix=[1.0 62.0 86.0 1.0 0.0], 
                     vcov=[13.7921    -0.115637    -0.257486    14.0947     7.9022
                           -0.115637   0.00798437  -0.00292449  -0.126011  -0.109049
                           -0.257486  -0.00292449   0.012907    -0.616651  -0.38812
                           14.0947    -0.126011    -0.616651    48.9021    30.2139
                            7.9022    -0.109049    -0.38812     30.2139    37.3171])
    @test gvif(duncan3) ≈ [2.209178, 5.297584, 5.098592] atol=1e-4
    @test gvif(duncan3; scale=true) ≈ [1.486330, 2.301648, 1.502666] atol=1e-5
end

@testset "utils" begin
   int = InterceptTerm{true}()
   noint = InterceptTerm{false}()
   xterm = term(:x)
   @test StatsModels._find_intercept(xterm) === nothing
   @test StatsModels._find_intercept(int) == 1
   @test StatsModels._find_intercept(noint) === nothing
   @test StatsModels._find_intercept(MatrixTerm((xterm, int))) == 2
   @test StatsModels.get_matrix_term(MatrixTerm(MatrixTerm((xterm, int)))) == MatrixTerm((xterm, int))
end
