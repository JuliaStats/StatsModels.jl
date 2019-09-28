@testset "Ambiguity detection" begin
    @test isempty(Test.detect_ambiguities(StatsModels))
end
