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

function missing_omit(d::T) where T<:ColumnTable
    nonmissings = trues(length(first(d)))
    for col in d
        _nonmissing!(nonmissings, col)
    end

    rows = findall(nonmissings)
    d_nonmissing =
        NamedTuple{Tables.names(T)}(tuple((copyto!(similar(col,
                                                           Missings.T(eltype(col)),
                                                           length(rows)),
                                                   view(col, rows)) for col in d)...))
    d_nonmissing, nonmissings
end

missing_omit(data::T, formula::AbstractTerm) where T<:ColumnTable =
    missing_omit(NamedTuple{tuple(termvars(formula)...)}(data))

function ModelFrame(f::FormulaTerm, data::ColumnTable;
                    mod::Type{Mod}=StatisticalModel, contrasts=Dict{Symbol,Any}()) where Mod
    data, _ = missing_omit(data, f)

    sch = schema(f, data, contrasts)
    f = apply_schema(f, sch, Mod)
    
    ModelFrame(f, sch, data, mod)
end

ModelFrame(f::FormulaTerm, data; mod=StatisticalModel, contrasts=Dict{Symbol,Any}()) =
    ModelFrame(f, columntable(data); mod=mod, contrasts=contrasts)

function model_matrix(f::FormulaTerm, data;
                      hints=Dict{Symbol,Any}(), mod::Type{Mod}=StatisticalModel) where Mod
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    f = has_schema(f) ? f : apply_schema(f, schema(f, data, hints), Mod)
    model_cols(f.rhs, columntable(data))
end
function StatsBase.model_response(f::FormulaTerm, data;
                                  hints=Dict{Symbol,Any}(),
                                  mod::Type{Mod}=StatisticalModel) where Mod
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    f = has_schema(f) ? f : apply_schema(f, schema(f, data, hints), Mod)
    model_cols(f.lhs, columntable(data))
end


model_matrix(mf::ModelFrame; data=mf.data) = model_cols(mf.f.rhs, data)
StatsBase.model_response(mf::ModelFrame; data=mf.data) = model_cols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = vectorize(termnames(mf.f.rhs))

"""
    setcontrasts!(mf::ModelFrame; kwargs...)
    setcontrasts!(mf::ModelFrame, contrasts::Dict{Symbol})

Update the contrasts used for coding categorical variables in
[`ModelFrame`](@ref) in place.  This is accomplished by computing a new schema
based on the provided contrasts and the `ModelFrame`'s data, and applying it to
the `ModelFrame`'s `FormulaTerm`.

Note that only the `ModelFrame` itself is mutated: because `AbstractTerm`s are
immutable, any changes will produce a copy.

"""
setcontrasts!(mf::ModelFrame; kwargs...) = setcontrasts!(mf, Dict(kwargs))
function setcontrasts!(mf::ModelFrame, contrasts::Dict{Symbol})
    # TODO: don't consume the whole table again if it's not needed
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



mutable struct ModelMatrix{T <: AbstractMatrix{<:AbstractFloat}}
    m::T
    assign::Vector{Int}
end

Base.size(mm::ModelMatrix, dim...) = size(mm.m, dim...)

function ModelMatrix{T}(mf::ModelFrame) where T<:AbstractMatrix{<:AbstractFloat}
    mat = model_matrix(mf)
    asgn = mapreduce((it)->first(it)*ones(width(last(it))), append!,
                     enumerate(vectorize(mf.f.rhs)), init=Int[])
    ModelMatrix(convert(T, mat), asgn)
end

ModelMatrix(mf::ModelFrame) = ModelMatrix{Matrix{Float64}}(mf)
