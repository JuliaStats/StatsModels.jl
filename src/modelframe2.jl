mutable struct ModelFrame{D}
    f::FormulaTerm
    schema
    data::D
end



## copied from DataFrames:
function _nonmissing!(res, col)
    # workaround until JuliaLang/julia#21256 is fixed
    eltype(col) >: Missing || return
    
    @inbounds for (i, el) in enumerate(col)
        res[i] &= !ismissing(el)
    end
end

function _nonmissing!(res, col::CategoricalArray{>: Missing})
    for (i, el) in enumerate(col.refs)
        res[i] &= el > 0
    end
end

_select(d::Data.Table, cols::NTuple{N,Symbol} where N) = NamedTuple{cols}(d)
_filter(d::T, rows) where T<:Data.Table = T(([col[rows] for col in d]..., ))

_size(d::Data.Table) = (length(first(d)), length(d))
_size(d::Data.Table, dim::Int) = _size(d)[dim]

## Default NULL handler.  Others can be added as keyword arguments
function missing_omit(d::T) where T<:Data.Table
    nonmissings = trues(_size(d, 1))
    for col in d
        _nonmissing!(nonmissings, col)
    end
    map(disallowmissing, _filter(d, nonmissings)), nonmissings
end

function ModelFrame(f::FormulaTerm, data::Data.Table)
    term_syms = (filter(x->x isa Symbol, mapreduce(termsyms, union, terms(f)))...,)
    data, _ = missing_omit(_select(data, term_syms))

    sch = FullRank(schema(f, data))
    f = apply_schema(f, sch)
    
    ModelFrame(f, sch, data)
end
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
    mat = reshape(mat, size(mat,1), :)
    asgn = mapreduce((it)->first(it)*ones(width(last(it))), append!,
                     enumerate(vectorize(mf.f.rhs)), init=Int[])
    ModelMatrix(convert(T, mat), asgn)
end

ModelMatrix(mf::ModelFrame) = ModelMatrix{Matrix{Float64}}(mf)
