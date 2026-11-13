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

_missing_omit(x::AbstractVector{T}) where T = copyto!(similar(x, nonmissingtype(T)), x)
_missing_omit(x::AbstractVector, rows) = _missing_omit(view(x, rows))

# loops instead of `map` over the `NamedTuple` so nothing is specialized on
# the table type (see `_modelcols_each` in terms.jl)
function missing_omit(@nospecialize(d::ColumnTable))
    nonmissings = trues(length(first(d)))
    for col in values(d)
        _nonmissing!(nonmissings, col)
    end
    cols = Vector{Any}(undef, length(d))
    if all(nonmissings)
        for (i, col) in enumerate(values(d))
            cols[i] = _missing_omit(col)
        end
    else
        rows = findall(nonmissings)
        for (i, col) in enumerate(values(d))
            cols[i] = _missing_omit(col, rows)
        end
    end
    d_nonmissing = NamedTuple{keys(d)}(Tuple(cols))
    d_nonmissing, nonmissings
end

function missing_omit(@nospecialize(data::ColumnTable), formula::AbstractTerm)
    vars = termvars(formula)
    # equivalent to NamedTuple{Tuple(vars)}(data), without Base's generator over
    # the table type
    cols = Vector{Any}(undef, length(vars))
    for (i, v) in enumerate(vars)
        cols[i] = getfield(data, v)
    end
    missing_omit(NamedTuple{Tuple(vars)}(Tuple(cols)))
end

function ModelFrame(f::FormulaTerm, @nospecialize(data::ColumnTable);
                    model::Type{M}=StatisticalModel, contrasts=Dict{Symbol,Any}()) where M

    msg = checknamesexist( f, data )
    if msg != ""
        throw(ArgumentError(msg))
    end

    data, _ = missing_omit(data, f)

    sch = schema(f, data, contrasts)
    f = apply_schema(f, sch, M)

    ModelFrame(f, sch, data, model)
end

ModelFrame(f::FormulaTerm, data; model=StatisticalModel, contrasts=Dict{Symbol,Any}()) =
    ModelFrame(f, columntable(data); model=model, contrasts=contrasts)

StatsAPI.modelmatrix(f::FormulaTerm, @nospecialize(data); kwargs...) = modelmatrix(f.rhs, data; kwargs...)

"""
    modelmatrix(t::AbstractTerm, data; hints=Dict(), mod=StatisticalModel)
    modelmatrix(mf::ModelFrame; data=mf.data)

Return the model matrix based on a term and a data source.  If the term `t` is a
[`FormulaTerm`](@ref), this uses the right-hand side (predictor terms) of the
formula; otherwise all columns are generated.  If a [`ModelFrame`](@ref) is
provided instead of an `AbstractTerm`, the wrapped table is used as the data
source by default.

Like [`response`](@ref), this will compute and apply a [`Schema`](@ref) before
calling [`modelcols`](@ref) if necessary.  The optional `hints` and `mod`
keyword arguments are passed to [`apply_schema`](@ref).

!!! note

    `modelmatrix` is provided as a convenience for interactive use.  For
    modeling packages that wish to support a formula-based interface, it is
    recommended to use the [`schema`](@ref) -- [`apply_schema`](@ref) --
    [`modelcols`](@ref) pipeline directly

"""
function StatsAPI.modelmatrix(t::Union{AbstractTerm, TupleTerm}, @nospecialize(data);
                               hints=Dict{Symbol,Any}(), mod::Type{M}=StatisticalModel) where M
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    t = has_schema(t) ? t : apply_schema(t, schema(t, data, hints), M)
    modelcols(collect_matrix_terms(t), columntable(data))
end

"""
    response(f::FormulaTerm, data; hints=Dict(), mod=StatisticalModel)
    response(mf::ModelFrame; data=mf.data)

Return the response (left-hand side) of a formula generated by a data source.
If a [`ModelFrame`](@ref) is provided instead of an `AbstractTerm`, the wrapped
table is used by default.

Like [`modelmatrix`](@ref), this will compute and apply a [`Schema`](@ref)
before calling [`modelcols`](@ref) if necessary.  The optional `hints` and `mod`
keyword arguments are passed to [`apply_schema`](@ref).

!!! note

    `response` is provided as a convenience for interactive use.  For
    modeling packages that wish to support a formula-based interface, it is
    recommended to use the [`schema`](@ref) -- [`apply_schema`](@ref) --
    [`modelcols`](@ref) pipeline directly

"""
function StatsAPI.response(f::FormulaTerm, @nospecialize(data);
                            hints=Dict{Symbol,Any}(),
                            mod::Type{M}=StatisticalModel) where M
    Tables.istable(data) ||
        throw(ArgumentError("expected data in a Table, got $(typeof(data))"))
    f = has_schema(f) ? f : apply_schema(f, schema(f, data, hints), M)
    modelcols(f.lhs, columntable(data))
end


StatsAPI.modelmatrix(mf::ModelFrame; data=mf.data) = modelcols(mf.f.rhs, data)
StatsAPI.response(mf::ModelFrame; data=mf.data) = modelcols(mf.f.lhs, data)

StatsAPI.coefnames(mf::ModelFrame) = vectorize(coefnames(mf.f.rhs))

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

    # warn of no-op for keys that don't correspond to known terms from old schema
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
