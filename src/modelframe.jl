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


"""
This is borrowed from [DataFrames.jl]()
`colnames` : some iterable collection of symbols
"""
function fuzzymatch(colnames, name::Symbol)
        ucname = uppercase(string(name))
        dist = [(levenshtein(uppercase(string(x)), ucname), x) for x in colnames]
        sort!(dist)
        c = [count(x -> x[1] <= i, dist) for i in 0:2]
        maxd = max(0, searchsortedlast(c, 8) - 1)
        return [s for (d, s) in dist if d <= maxd]
end

"""
Raise an ArgumentError with a nice-ish error message if the Symbol `name` isn't a column name in `table`.
"""
function checkcol(table, name :: Symbol)
    i = Tables.columnindex(table, name)
    if i == 0 # if no such column
        names = Tables.columnnames(table)
        nearestnames = join(fuzzymatch(names, name),", " )
        throw(ArgumentError("There isn't a variable called '$name' in your data; the nearest names appear to be: $nearestnames" ))
    end
end

"""
Check that each name in the given model `f` exists in the data source `t`; throw an ArgumentError otherwise.
`t` is something that implements the `Tables` interface.
"""
function checknamesexist(f :: FormulaTerm, t)
    if ! Tables.istable(t)
        throw(ArgumentError( "$(typeof(t)) isn't a valid Table type" ))
    end
    for n in StatsModels.termvars(f)
        checkcol(t, n)
    end    
end
    


function ModelFrame(f::FormulaTerm, data::ColumnTable;
                    model::Type{M}=StatisticalModel, contrasts=Dict{Symbol,Any}()) where M
    
    checknamesexist( f, data )

    data, _ = missing_omit(data, f)

    sch = schema(f, data, contrasts)
    f = apply_schema(f, sch, M)
    
    ModelFrame(f, sch, data, model)
end

ModelFrame(f::FormulaTerm, data; model=StatisticalModel, contrasts=Dict{Symbol,Any}()) =
    ModelFrame(f, columntable(data); model=model, contrasts=contrasts)

StatsBase.modelmatrix(f::FormulaTerm, data; kwargs...) = modelmatrix(f.rhs, data; kwargs...)

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
function StatsBase.modelmatrix(t::Union{AbstractTerm, TupleTerm}, data;
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
