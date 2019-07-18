@testset "ModelFrame (legacy API)" begin

    @testset "#133" begin
        df = (x = rand(12),
              y = categorical(repeat(1:3, inner=4)),
              z = categorical(repeat(1:2, outer=6)));
        f = @formula(x ~ y * z);
        mf = ModelFrame(f, df)
        mm = ModelMatrix(mf)
        @test mm.assign == [1, 2, 2, 3, 4, 4]
    end
    
end
