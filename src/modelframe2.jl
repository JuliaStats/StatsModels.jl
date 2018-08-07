mutable struct ModelFrame{D}
    f::FormulaTerm
    schema
    data::D
end

ModelFrame(f::FormulaTerm, schema, data) = ModelFrame{typeof(data)}(apply_schema(f, schema), schema, data)
ModelFrame(f::FormulaTerm, data) = ModelFrame(f, schema(f, data), data)

model_matrix(mf::ModelFrame; data=mf.data) = model_cols(mf.f.rhs, data)
StatsBase.model_response(mf::ModelFrame; data=mf.data) = model_cols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = termnames(mf.f.rhs)
