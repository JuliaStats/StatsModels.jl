mutable struct ModelFrame{D,M}
    f::FormulaTerm
    schema
    data::D
    model::Type{M}
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

_select(d::ColumnTable, cols::NTuple{N,Symbol} where N) = NamedTuple{cols}(d)
_select(d::ColumnTable, cols::Vector{Symbol}) = _select(d, tuple(cols...))
_filter(d::T, rows) where T<:ColumnTable = T(([col[rows] for col in d]..., ))

_size(d::ColumnTable) = (length(first(d)), length(d))
_size(d::ColumnTable, dim::Int) = _size(d)[dim]

## Default NULL handler.  Others can be added as keyword arguments
function missing_omit(d::T) where T<:ColumnTable
    nonmissings = trues(_size(d, 1))
    for col in d
        _nonmissing!(nonmissings, col)
    end
    map(disallowmissing, _filter(d, nonmissings)), nonmissings
end

missing_omit(data::T, formula::AbstractTerm) where T<:ColumnTable =
    missing_omit(_select(data, termvars(formula)))

function ModelFrame(f::FormulaTerm, data::ColumnTable;
                    mod::Type{Mod}=StatisticalModel, contrasts=Dict{Symbol,Any}()) where Mod
    data, _ = missing_omit(data, f)

    sch = schema(f, data, contrasts)
    f = apply_schema(f, sch, Mod)
    
    ModelFrame(f, sch, data, mod)
end

ModelFrame(f::FormulaTerm, data; mod=StatisticalModel, contrasts=Dict{Symbol,Any}()) =
    ModelFrame(f, columntable(data); mod=mod, contrasts=contrasts)

model_matrix(mf::ModelFrame; data=mf.data) = model_cols(mf.f.rhs, data)
StatsBase.model_response(mf::ModelFrame; data=mf.data) = model_cols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = vectorize(termnames(mf.f.rhs))

setcontrasts!(mf::ModelFrame; kwargs...) = setcontrasts!(mf, Dict(kwargs))
function setcontrasts!(mf::ModelFrame, contrasts::Dict{Symbol})
    new_schema = schema([term(k) for k in keys(contrasts)], mf.data, contrasts)

    # warn of no-op for keys that dont correspond to known terms from old schema
    unknown_keys = [k for k in keys(new_schema) if !haskey(mf.schema, k)]
    if !isempty(unknown_keys)
        unknown_keys_str = join(unknown_keys, ", ", " and ")
        @warn "setcontrasts! for terms " * unknown_keys_str *
            " has no effect since they are not found in original schema"
    end

    # apply only the re-mapped terms
    mf.f = apply_schema(mf.f, new_schema, mf.model)
    merge!(mf.schema, new_schema)
    mf
end



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
