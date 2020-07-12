"""
    ModelFrame(formula, data; model=StatisticalModel, contrasts=Dict())

Wrapper that encapsulates a `FormulaTerm`, schema, data table, and model type.

This wrapper encapsulates all the information that's required to transform data
of the same structure as the wrapped data frame into a model matrix (the
`FormulaTerm`), as well as the information about how that formula term was
instantiated (the schema and model type)

Creating a model frame involves first extracting the [`schema`](@ref) for the
data (using any contrasts provided as hints), and then applying that schema with
[`apply_schema`](@ref) to the formula in the context of the provided model type.

# Constructors

```julia
ModelFrame(f::FormulaTerm, data; model::Type{M} = StatisticalModel, contrasts::Dict = Dict())
```

# Fields

* `f::FormulaTerm`: Formula whose left hand side is the *response* and right hand
  side are the *predictors*.
* `schema::Any`: The schema that was applied to generate `f`.
* `data::D`: The data table being modeled.  The only restriction is that `data` 
  is a table (`Tables.istable(data) == true`)
* `model::Type{M}`: The type of the model that will be fit from this model frame.

# Examples

```julia
julia> df = (x = 1:4, y = 5:8)
julia> mf = ModelFrame(@formula(y ~ 1 + x), df)
```
"""
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
    res .&= .!ismissing.(col)
end


function missing_omit(d::T) where T<:ColumnTable
    nonmissings = trues(length(first(d)))
    for col in d
        _nonmissing!(nonmissings, col)
    end

    rows = findall(nonmissings)
    d_nonmissing =
        NamedTuple{Tables.names(T)}(tuple((copyto!(similar(col,
                                                           Base.nonmissingtype(eltype(col)),
                                                           length(rows)),
                                                   view(col, rows)) for col in d)...))
    d_nonmissing, nonmissings
end

missing_omit(data::T, formula::AbstractTerm) where T<:ColumnTable =
    missing_omit(NamedTuple{tuple(termvars(formula)...)}(data))

function ModelFrame(f::FormulaTerm, data::ColumnTable;
                    model::Type{M}=StatisticalModel, contrasts=Dict{Symbol,Any}()) where M
    data, _ = missing_omit(data, f)

    sch = schema(f, data, contrasts)
    f = apply_schema(f, sch, M)
    
    ModelFrame(f, sch, data, model)
end

ModelFrame(f::FormulaTerm, data; model=StatisticalModel, contrasts=Dict{Symbol,Any}()) =
    ModelFrame(f, columntable(data); model=model, contrasts=contrasts)

StatsBase.modelmatrix(f::FormulaTerm, data; kwargs...) = modelmatrix(f.rhs, data; kwargs...)

function StatsBase.modelmatrix(t::TermOrTerms, data;
                               hints=Dict{Symbol,Any}(), mod::Type{M}=StatisticalModel) where M
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    t = has_schema(t) ? t : apply_schema(t, schema(t, data, hints), M)
    modelcols(collect_matrix_terms(t), columntable(data))
end
function StatsBase.response(f::FormulaTerm, data;
                            hints=Dict{Symbol,Any}(),
                            mod::Type{M}=StatisticalModel) where M
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    f = has_schema(f) ? f : apply_schema(f, schema(f, data, hints), M)
    modelcols(f.lhs, columntable(data))
end


StatsBase.modelmatrix(mf::ModelFrame; data=mf.data) = modelcols(mf.f.rhs, data)
StatsBase.response(mf::ModelFrame; data=mf.data) = modelcols(mf.f.lhs, data)

StatsBase.coefnames(mf::ModelFrame) = vectorize(coefnames(mf.f.rhs))

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


"""
    ModelMatrix(mf::ModelFrame)

Convert a `ModelFrame` into a numeric matrix suitable for modeling

# Fields

* `m::AbstractMatrix{<:AbstractFloat}`: the generated numeric matrix
* `assign::Vector{Int}` the index of the term corresponding to each column of `m`.

# Constructors

```julia
ModelMatrix(mf::ModelFrame)
# Specify the type of the resulting matrix (default Matrix{Float64})
ModelMatrix{T <: AbstractMatrix{<:AbstractFloat}}(mf::ModelFrame)
```
"""
mutable struct ModelMatrix{T <: AbstractMatrix{<:AbstractFloat}}
    m::T
    assign::Vector{Int}
end

Base.size(mm::ModelMatrix, dim...) = size(mm.m, dim...)

asgn(f::FormulaTerm) = asgn(f.rhs)
asgn(mt::MatrixTerm) = asgn(mt.terms)
asgn(t) = mapreduce(((i,t), ) -> i*ones(width(t)),
                    append!,
                    enumerate(vectorize(t)),
                    init=Int[])

function ModelMatrix{T}(mf::ModelFrame) where T<:AbstractMatrix{<:AbstractFloat}
    mat = modelmatrix(mf)
    ModelMatrix(convert(T, mat), asgn(mf.f))
end

ModelMatrix(mf::ModelFrame) = ModelMatrix{Matrix{Float64}}(mf)
