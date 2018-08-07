mutable struct ModelFrame{D}
    f::FormulaTerm
    schema
    data::D
end

ModelFrame(f::FormulaTerm, schema, data) =
    ModelFrame{typeof(data)}(apply_schema(f, schema), schema, data)
ModelFrame(f::FormulaTerm, data) = ModelFrame(f, FullRank(schema(f, data)), data)

model_matrix(mf::ModelFrame; data=mf.data) = model_cols(mf.f.rhs, data)
StatsBase.model_response(mf::ModelFrame; data=mf.data) = model_cols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = termnames(mf.f.rhs)



const AbstractFloatMatrix{T<:AbstractFloat} =  AbstractMatrix{T}

mutable struct ModelMatrix{T <: AbstractFloatMatrix}
    m::T
    assign::Vector{Int}
end

function ModelMatrix{T}(mf::ModelFrame) where T<:AbstractFloatMatrix
    mat = model_matrix(mf)
    asgn = mapreduce((i,term)->repeat(i, width(term), append!, enumerate(mf.f.rhs)))
    ModelMatrix{T}(mat, asgn)
end
