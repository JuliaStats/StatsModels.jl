"""
Wrapper which combines Formula (Terms) and an AbstractDataTable

This wrapper encapsulates all the information that's required to transform data
of the same structure as the wrapped data frame into a model matrix.  This goes
above and beyond what's expressed in the `Formula` itself, for instance
including information on how each categorical variable should be coded.

Creating a `ModelFrame` first parses the `Formula` into `Terms`, checks which
variables are categorical and determines the appropriate contrasts to use, and
then creates the necessary contrasts matrices and stores the results.

# Constructors

```julia
ModelFrame(f::Formula, df::AbstractDataTable; contrasts::Dict = Dict())
ModelFrame(ex::Expr, d::AbstractDataTable; contrasts::Dict = Dict())
ModelFrame(terms::Terms, df::AbstractDataTable; contrasts::Dict = Dict())
# Inner constructors:
ModelFrame(df::AbstractDataTable, terms::Terms, missing::BitArray)
ModelFrame(df::AbstractDataTable, terms::Terms, missing::BitArray, contrasts::Dict{Symbol, ContrastsMatrix})
```

# Arguments

* `f::Formula`: Formula whose left hand side is the *response* and right hand
  side are the *predictors*.
* `df::AbstractDataTable`: The data being modeled.  This is used at this stage
  to determine which variables are categorical, and otherwise held for
  [`ModelMatrix`](@ref).
* `contrasts::Dict`: An optional Dict of contrast codings for each categorical
  variable.  Any unspecified variables will have [`DummyCoding`](@ref).  As a
  keyword argument, these can be either instances of a subtype of
  [`AbstractContrasts`](@ref), or a [`ContrastsMatrix`](@ref).  For the inner
  constructor, they must be [`ContrastsMatrix`](@ref)es.
* `ex::Expr`: An expression which will be converted into a `Formula`.
* `terms::Terms`: For inner constructor, the parsed `Terms` from the `Formula`.
* `missing::BitArray`: For inner constructor, indicates whether each row of `df`
  contains any missing data.

# Examples

```julia
julia> df = DataTable(x = 1:4, y = 5:9)
julia> mf = ModelFrame(y ~ 1 + x, df)
```

"""
type ModelFrame
    df::AbstractDataTable
    terms::Terms
    msng::BitArray
    ## mapping from df keys to contrasts matrices
    contrasts::Dict{Symbol, ContrastsMatrix}
end

is_categorical{T<:Real}(::AbstractArray{T}) = false
typealias NullableReal{T<:Real} Nullable{T}
is_categorical{T<:NullableReal}(::AbstractArray{T}) = false
is_categorical(::AbstractArray) = true

## Check for non-redundancy of columns.  For instance, if x is a factor with two
## levels, it should be expanded into two columns in y~0+x but only one column
## in y~1+x.  The default is the rank-reduced form (contrasts for n levels only
## produce n-1 columns).  In general, an evaluation term x within a term
## x&y&... needs to be "promoted" to full rank if y&... hasn't already been
## included (either explicitly in the Terms or implicitly by promoting another
## term like z in z&y&...).
##
## This modifies the Terms, setting `trms.is_non_redundant = true` for all non-
## redundant evaluation terms.
function check_non_redundancy!(trms::Terms, df::AbstractDataTable)

    (n_eterms, n_terms) = size(trms.factors)

    encountered_columns = Vector{eltype(trms.factors)}[]

    if trms.intercept
        push!(encountered_columns, zeros(eltype(trms.factors), n_eterms))
    end

    for i_term in 1:n_terms
        for i_eterm in 1:n_eterms
            ## only need to check eterms that are included and can be promoted
            ## (e.g., categorical variables that expand to multiple mm columns)
            if Bool(trms.factors[i_eterm, i_term]) && is_categorical(df[trms.eterms[i_eterm]])
                dropped = trms.factors[:,i_term]
                dropped[i_eterm] = 0

                if findfirst(encountered_columns, dropped) == 0
                    trms.is_non_redundant[i_eterm, i_term] = true
                    push!(encountered_columns, dropped)
                end

            end
        end
        ## once we've checked all the eterms in this term, add it to the list
        ## of encountered terms/columns
        push!(encountered_columns, Compat.view(trms.factors, :, i_term))
    end

    return trms.is_non_redundant
end

const DEFAULT_CONTRASTS = DummyCoding

_unique(x::CategoricalArray) = unique(x)
_unique(x::NullableCategoricalArray) = [get(l) for l in unique(x) if !isnull(l)]

function _unique{T<:Nullable}(x::AbstractArray{T})
    levs = [get(l) for l in unique(x) if !isnull(l)]
    try; sort!(levs); end
    return levs
end

function _unique(x::AbstractArray)
    levs = unique(x)
    try; sort!(levs); end
    return levs
end

## Set up contrasts:
## Combine actual DF columns and contrast types if necessary to compute the
## actual contrasts matrices, levels, and term names (using DummyCoding
## as the default)
function evalcontrasts(df::AbstractDataTable, contrasts::Dict = Dict())
    evaledContrasts = Dict()
    for (term, col) in eachcol(df)
        is_categorical(col) || continue
        evaledContrasts[term] = ContrastsMatrix(haskey(contrasts, term) ?
                                                contrasts[term] :
                                                DEFAULT_CONTRASTS(),
                                                _unique(col))
    end
    return evaledContrasts
end

## Default NULL handler.  Others can be added as keyword arguments
function null_omit(df::DataTable)
    cc = complete_cases(df)
    df[cc,:], cc
end

_droplevels!(x::Any) = x
_droplevels!(x::Union{CategoricalArray, NullableCategoricalArray}) = droplevels!(x)

function ModelFrame(trms::Terms, d::AbstractDataTable;
                    contrasts::Dict = Dict())
    df, msng = null_omit(DataTable(map(x -> d[x], trms.eterms)))
    names!(df, convert(Vector{Symbol}, map(string, trms.eterms)))
    for c in eachcol(df) _droplevels!(c[2]) end

    evaledContrasts = evalcontrasts(df, contrasts)

    ## Check for non-redundant terms, modifying terms in place
    check_non_redundancy!(trms, df)

    ModelFrame(df, trms, msng, evaledContrasts)
end

ModelFrame(df::AbstractDataTable, term::Terms, msng::BitArray) = ModelFrame(df, term, msng, evalcontrasts(df))
ModelFrame(f::Formula, d::AbstractDataTable; kwargs...) = ModelFrame(Terms(f), d; kwargs...)
ModelFrame(ex::Expr, d::AbstractDataTable; kwargs...) = ModelFrame(Formula(ex), d; kwargs...)

"""
    setcontrasts!(mf::ModelFrame, new_contrasts::Dict)

Modify the contrast coding system of a ModelFrame in place.
"""
function setcontrasts!(mf::ModelFrame, new_contrasts::Dict)
    new_contrasts = Dict([ Pair(col, ContrastsMatrix(contr, _unique(mf.df[col])))
                      for (col, contr) in filter((k,v)->haskey(mf.df, k), new_contrasts) ])

    mf.contrasts = merge(mf.contrasts, new_contrasts)
    return mf
end
setcontrasts!(mf::ModelFrame; kwargs...) = setcontrasts!(mf, Dict(kwargs))

"""
    StatsBase.model_response(mf::ModelFrame)
Extract the response column, if present.  `DataVector` or
`PooledDataVector` columns are converted to `Array`s
"""
function StatsBase.model_response(mf::ModelFrame)
    if mf.terms.response
        convert(Array, mf.df[mf.terms.eterms[1]])
    else
        error("Model formula one-sided")
    end
end


"""
    termnames(term::Symbol, col)
Returns a vector of strings with the names of the coefficients
associated with a term.  If the column corresponding to the term
is not a `CategoricalArray` or `NullableCategoricalArray`,
a one-element vector is returned.
"""
termnames(term::Symbol, col) = [string(term)]
function termnames(term::Symbol, mf::ModelFrame; non_redundant::Bool = false)
    if haskey(mf.contrasts, term)
        termnames(term, mf.df[term],
                  non_redundant ?
                  ContrastsMatrix{FullDummyCoding}(mf.contrasts[term]) :
                  mf.contrasts[term])
    else
        termnames(term, mf.df[term])
    end
end

termnames(term::Symbol, col::Any, contrast::ContrastsMatrix) =
    ["$term: $name" for name in contrast.termnames]


function expandtermnames(term::Vector)
    if length(term) == 1
        return term[1]
    else
        return foldr((a,b) -> vec([string(lev1, " & ", lev2) for
                                   lev1 in a,
                                   lev2 in b]),
                     term)
    end
end


"""
    coefnames(mf::ModelFrame)
Returns a vector of coefficient names constructed from the Terms
member and the types of the evaluation columns.
"""
function coefnames(mf::ModelFrame)
    terms = droprandomeffects(dropresponse!(mf.terms))

    ## strategy mirrors ModelMatrx constructor:
    eterm_names = @compat Dict{Tuple{Symbol,Bool}, Vector{Compat.UTF8String}}()
    term_names = Vector{Compat.UTF8String}[]

    if terms.intercept
        push!(term_names, Compat.UTF8String["(Intercept)"])
    end

    factors = terms.factors

    for (i_term, term) in enumerate(terms.terms)

        ## names for columns for eval terms
        names = Vector{Compat.UTF8String}[]

        ff = Compat.view(factors, :, i_term)
        eterms = Compat.view(terms.eterms, ff)
        non_redundants = Compat.view(terms.is_non_redundant, ff, i_term)

        for (et, nr) in zip(eterms, non_redundants)
            if !haskey(eterm_names, (et, nr))
                eterm_names[(et, nr)] = termnames(et, mf, non_redundant=nr)
            end
            push!(names, eterm_names[(et, nr)])
        end
        push!(term_names, expandtermnames(names))
    end

    reduce(vcat, Vector{Compat.UTF8String}(), term_names)
end
