mutable struct ModelFrame{D}
    f::FormulaTerm
    schema
    data::D
end


ModelFrame(f::FormulaTerm, schema, data::Data.Table) =
    ModelFrame{typeof(data)}(apply_schema(f, schema), schema, data)
ModelFrame(f::FormulaTerm, data::Data.Table) = ModelFrame(f, FullRank(schema(f, data)), data)
ModelFrame(f::FormulaTerm, data) = ModelFrame(f, Data.stream!(data, Data.Table))

model_matrix(mf::ModelFrame; data=mf.data) = model_cols(mf.f.rhs, data)
StatsBase.model_response(mf::ModelFrame; data=mf.data) = model_cols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = termnames(mf.f.rhs)



const AbstractFloatMatrix{T<:AbstractFloat} =  AbstractMatrix{T}

mutable struct ModelMatrix{T <: AbstractFloatMatrix}
    m::T
    assign::Vector{Int}
end

Base.size(mm::ModelMatrix) = size(mm.m)
Base.size(mm::ModelMatrix, dim...) = size(mm.m, dim...)

function ModelMatrix{T}(mf::ModelFrame) where T<:AbstractFloatMatrix
    mat = model_matrix(mf)
    asgn = mapreduce((it)->first(it)*ones(width(last(it))), append!,
                     enumerate(vectorize(mf.f.rhs)), init=Int[])
    ModelMatrix{T}(mat, asgn)
end

ModelMatrix(mf::ModelFrame) = ModelMatrix{Matrix{Float64}}(mf)
