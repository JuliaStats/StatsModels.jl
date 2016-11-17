type ModelFrame
    df::AbstractDataFrame
    terms::Terms
    msng::BitArray
    ## mapping from df keys to contrasts matrices
    contrasts::Dict{Symbol, ContrastsMatrix}
end

is_categorical(::Union{CategoricalArray, NullableCategoricalArray}) = true
is_categorical(::Any) = false

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
function check_non_redundancy!(trms::Terms, df::AbstractDataFrame)

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

## Set up contrasts:
## Combine actual DF columns and contrast types if necessary to compute the
## actual contrasts matrices, levels, and term names (using DummyCoding
## as the default)
function evalcontrasts(df::AbstractDataFrame, contrasts::Dict = Dict())
    evaledContrasts = Dict()
    for (term, col) in eachcol(df)
        is_categorical(col) || continue
        evaledContrasts[term] = ContrastsMatrix(haskey(contrasts, term) ?
                                                contrasts[term] :
                                                DEFAULT_CONTRASTS(),
                                                col)
    end
    return evaledContrasts
end

## Default NULL handler.  Others can be added as keyword arguments
function null_omit(df::DataFrame)
    cc = complete_cases(df)
    df[cc,:], cc
end

_droplevels!(x::Any) = x
_droplevels!(x::Union{CategoricalArray, NullableCategoricalArray}) = droplevels!(x)

function ModelFrame(trms::Terms, d::AbstractDataFrame;
                    contrasts::Dict = Dict())
    df, msng = null_omit(DataFrame(map(x -> d[x], trms.eterms)))
    names!(df, convert(Vector{Symbol}, map(string, trms.eterms)))
    for c in eachcol(df) _droplevels!(c[2]) end

    evaledContrasts = evalcontrasts(df, contrasts)

    ## Check for non-redundant terms, modifying terms in place
    check_non_redundancy!(trms, df)

    ModelFrame(df, trms, msng, evaledContrasts)
end

ModelFrame(df::AbstractDataFrame, term::Terms, msng::BitArray) = ModelFrame(df, term, msng, evalcontrasts(df))
ModelFrame(f::Formula, d::AbstractDataFrame; kwargs...) = ModelFrame(Terms(f), d; kwargs...)
ModelFrame(ex::Expr, d::AbstractDataFrame; kwargs...) = ModelFrame(Formula(ex), d; kwargs...)

"""
    setcontrasts!(mf::ModelFrame, new_contrasts::Dict)

Modify the contrast coding strategy of a ModelFrame in place.
"""
function setcontrasts!(mf::ModelFrame, new_contrasts::Dict)
    new_contrasts = Dict([ Pair(col, ContrastsMatrix(contr, mf.df[col]))
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
