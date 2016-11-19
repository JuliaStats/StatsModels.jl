
typealias AbstractFloatMatrix{T<:AbstractFloat} AbstractMatrix{T}

"""
Convert a `ModelFrame` into a numeric matrix suitable for modeling

**Constructors**

```julia
ModelMatrix(mf::ModelFrame)
# Specify the type of the resulting matrix (default Matrix{Float64})
ModelMatrix{T <: AbstractFloatMatrix}(mf::ModelFrame)
```

"""
type ModelMatrix{T <: AbstractFloatMatrix}
    m::T
    assign::Vector{Int}
end

Base.size(mm::ModelMatrix) = size(mm.m)
Base.size(mm::ModelMatrix, dim...) = size(mm.m, dim...)



## construct model matrix columns from model frame + name (checks for contrasts)
function modelmat_cols{T<:AbstractFloatMatrix}(::Type{T}, name::Symbol, mf::ModelFrame; non_redundant::Bool = false)
    if haskey(mf.contrasts, name)
        modelmat_cols(T, mf.df[name],
                      non_redundant ?
                      ContrastsMatrix{FullDummyCoding}(mf.contrasts[name]) :
                      mf.contrasts[name])
    else
        modelmat_cols(T, mf.df[name])
    end
end

modelmat_cols{T<:AbstractFloatMatrix}(::Type{T}, v::AbstractVector) =
    convert(T, reshape(v, length(v), 1))
# FIXME: this inefficient method should not be needed, cf. JuliaLang/julia#18264
modelmat_cols{T<:AbstractFloatMatrix}(::Type{T}, v::NullableVector) =
    convert(T, Matrix(reshape(v, length(v), 1)))

"""
    modelmat_cols{T<:AbstractFloatMatrix}(::Type{T}, v::PooledDataVector, contrast::ContrastsMatrix)

Construct `ModelMatrix` columns of type `T` based on specified contrasts, ensuring that
levels align properly.
"""
function modelmat_cols{T<:AbstractFloatMatrix}(::Type{T},
                                               v::Union{CategoricalVector, NullableCategoricalVector},
                                               contrast::ContrastsMatrix)
    ## make sure the levels of the contrast matrix and the categorical data
    ## are the same by constructing a re-indexing vector. Indexing into
    ## reindex with v.refs will give the corresponding row number of the
    ## contrast matrix
    reindex = [findfirst(contrast.levels, l) for l in levels(v)]
    contrastmatrix = convert(T, contrast.matrix)
    return indexrows(contrastmatrix, reindex[v.refs])
end

indexrows(m::SparseMatrixCSC, ind::Vector{Int}) = m'[:, ind]'
indexrows(m::AbstractMatrix, ind::Vector{Int}) = m[ind, :]

"""
    expandcols{T<:AbstractFloatMatrix}(trm::Vector{T})
Create pairwise products of columns from a vector of matrices
"""
function expandcols{T<:AbstractFloatMatrix}(trm::Vector{T})
    if length(trm) == 1
        trm[1]
    else
        a = trm[1]
        b = expandcols(trm[2 : end])
        reduce(hcat, [broadcast(*, a, Compat.view(b, :, j)) for j in 1 : size(b, 2)])
    end
end

"""
    droprandomeffects(trms::Terms)
Expressions of the form `(a|b)` are "random-effects" terms and are not
incorporated in the ModelMatrix.  This function checks for such terms and,
if any are present, drops them from the `Terms` object.
"""
function droprandomeffects(trms::Terms)
    retrms = Bool[Meta.isexpr(t, :call) && t.args[1] == :| for t in trms.terms]
    if !any(retrms)  # return trms unchanged
        trms
    elseif all(retrms) && !trms.response   # return an empty Terms object
        Terms(Any[],Any[],Array(Bool, (0,0)),Array(Bool, (0,0)), Int[], false, trms.intercept)
    else
        # the rows of `trms.factors` correspond to `eterms`, the columns to `terms`
        # After dropping random-effects terms we drop any eterms whose rows are all false
        ckeep = !retrms                 # columns to retain
        facs = trms.factors[:, ckeep]
        rkeep = vec(sum(facs, 2) .> 0)
        Terms(trms.terms[ckeep], trms.eterms[rkeep], facs[rkeep, :],
              trms.is_non_redundant[rkeep, ckeep],
              trms.order[ckeep], trms.response, trms.intercept)
    end
end

"""
    dropresponse!(trms::Terms)
Drop the response term, `trms.eterms[1]` and the first row and column
of `trms.factors` if `trms.response` is true.
"""
function dropresponse!(trms::Terms)
    if trms.response
        ckeep = 2:size(trms.factors, 2)
        rkeep = vec(any(trms.factors[:, ckeep], 2))
        Terms(trms.terms, trms.eterms[rkeep], trms.factors[rkeep, ckeep],
              trms.is_non_redundant[rkeep, ckeep], trms.order[ckeep], false, trms.intercept)
    else
        trms
    end
end

"""
    ModelMatrix{T<:AbstractFloatMatrix}(mf::ModelFrame)
Create a `ModelMatrix` of type `T` (default `Matrix{Float64}`) from the
`terms` and `df` members of `mf`.

This is basically a map-reduce where terms are mapped to columns by `cols`
and reduced by `hcat`.  During the collection of the columns the `assign`
vector is created.  `assign` maps columns of the model matrix to terms in
the model frame.  It can also be considered as mapping coefficients to
terms and, hence, to names.

If there is an intercept in the model, that column occurs first and its
`assign` value is zero.

Mixed-effects models include "random-effects" terms which are ignored when
creating the model matrix.
"""
@compat function (::Type{ModelMatrix{T}}){T<:AbstractFloatMatrix}(mf::ModelFrame)
    dfrm = mf.df
    terms = droprandomeffects(dropresponse!(mf.terms))

    blocks = T[]
    assign = Int[]
    if terms.intercept
        push!(blocks, ones(size(dfrm, 1), 1))  # columns of 1's is first block
        push!(assign, 0)                       # this block corresponds to term zero
    end

    factors = terms.factors

    ## Map eval. term name + redundancy bool to cached model matrix columns
    eterm_cols = @compat Dict{Tuple{Symbol,Bool}, T}()
    ## Accumulator for each term's vector of eval. term columns.

    ## TODO: this method makes multiple copies of the data in the ModelFrame:
    ## first in term_cols (1-2x per evaluation term, depending on redundancy),
    ## second in constructing the matrix itself.

    ## turn each term into a vector of mm columns for its eval. terms, using
    ## "promoted" full-rank versions of categorical columns for non-redundant
    ## eval. terms:
    for (i_term, term) in enumerate(terms.terms)
        term_cols = T[]
        ## Pull out the eval terms, and the non-redundancy flags for this term
        ff = Compat.view(factors, :, i_term)
        eterms = Compat.view(terms.eterms, ff)
        non_redundants = Compat.view(terms.is_non_redundant, ff, i_term)
        ## Get cols for each eval term (either previously generated, or generating
        ## and storing as necessary)
        for (et, nr) in zip(eterms, non_redundants)
            if ! haskey(eterm_cols, (et, nr))
                eterm_cols[(et, nr)] = modelmat_cols(T, et, mf, non_redundant=nr)
            end
            push!(term_cols, eterm_cols[(et, nr)])
        end
        push!(blocks, expandcols(term_cols))
        append!(assign, fill(i_term, size(blocks[end], 2)))
    end

    if isempty(blocks)
        error("Could not construct model matrix. Resulting matrix has 0 columns.")
    end

    I = size(dfrm, 1)
    J = mapreduce(x -> size(x, 2), +, blocks)
    X = similar(blocks[1], I, J)
    i = 1
    for block in blocks
        len = size(block, 2)
        X[:, i:(i + len - 1)] = block
        i += len
    end
    ModelMatrix{T}(X, assign)
end
ModelMatrix(mf::ModelFrame) = ModelMatrix{Matrix{Float64}}(mf)
