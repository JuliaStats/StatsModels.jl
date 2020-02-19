# Specify contrasts for coding categorical data in model matrix. Contrasts types
# are a subtype of AbstractContrasts. ContrastsMatrix types hold a contrast
# matrix, levels, and term names and provide the interface for creating model
# matrix columns and coefficient names.
#
# Contrasts types themselves can be instantiated to provide containers for
# contrast settings (currently, just the base level).
#
# ModelFrame will hold a Dict{Symbol, ContrastsMatrix} that maps column
# names to contrasts.
#
# ModelMatrix will check this dict when evaluating terms, falling back to a
# default for any categorical data without a specified contrast.


"""
Interface to describe contrast coding systems for categorical variables.

Concrete subtypes of `AbstractContrasts` describe a particular way of converting a
categorical data vector into numeric columns in a `ModelMatrix`. Each
instantiation optionally includes the levels to generate columns for and the base
level. If not specified these will be taken from the data when a `ContrastsMatrix` is
generated (during `ModelFrame` construction).

# Constructors

For `C <: AbstractContrast`:

```julia
C()                                     # levels are inferred later
C(levels = ::Vector{Any})               # levels checked against data later
C(base = ::Any)                         # specify base level
C(levels = ::Vector{Any}, base = ::Any) # specify levels and base
```

# Arguments

* `levels`: Optionally, the data levels can be specified here.  This allows you
  to specify the order of the levels.  If specified, the levels will be checked
  against the levels actually present in the data when the `ContrastsMatrix` is
  constructed. Any mismatch will result in an error, because levels missing in
  the data would lead to empty columns in the model matrix, and levels missing
  from the contrasts would lead to empty or undefined rows.
* `base`: The base level may also be specified.  The actual interpretation
  of this depends on the particular contrast type, but in general it can be
  thought of as a "reference" level.  It defaults to the first level.

# Contrast coding systems

* [`DummyCoding`](@ref) - Code each non-base level as a 0-1 indicator column.
* [`EffectsCoding`](@ref) - Code each non-base level as 1, and base as -1.
* [`HelmertCoding`](@ref) - Code each non-base level as the difference from the
  mean of the lower levels
* [`SeqDiffCoding`](@ref) - Code for differences between sequential levels of
  the variable.
* [`HypothesisCoding`](@ref) - Manually specify contrasts via a hypothesis 
  matrix, which gives the weighting for the average response for each level
* [`StatsModels.ContrastsCoding`](@ref) - Manually specify contrasts matrix,
  which is directly copied into the model matrix.

The last two coding types, `HypothesisCoding` and `StatsModels.ContrastsCoding`,
provide a way to manually specify a contrasts matrix. For a variable `x` with
`k` levels, a contrasts matrix `M` is a `k×k-1` matrix, that maps the `k` levels
onto `k-1` model matrix columns.  Specifically, let `X` be the full-rank
indicator matrix for `x`, where `X[i,j] = 1` if `x[i] == levels(x)[j]`, and 0
otherwise. Then the model matrix columns generated by the contrasts matrix `M`
are `Y = X * M`.

The *hypothesis matrix* is the `k-1×k` matrix that gives the weighted
combinations of group mean responses that are represented by regression
coefficients for the generated contrasts.  The contrasts matrix is the
generalized pseudo-inverse (e.g. `LinearAlgebra.pinv`) of the hypothesis matrix.
See [`HypothesisCoding`](@ref) or Schad et al. (2020) for more information.

# Extending

The easiest way to specify custom contrasts is with `HypothesisCoding` or
`StatsModels.ContrastsCoding`.  But if you want to actually implement a custom
contrast coding system, you can subtype `AbstractContrasts`.  This requires a
constructor, a `contrasts_matrix` method for constructing the actual contrasts
matrix that maps from levels to `ModelMatrix` column values, and (optionally) a
`termnames` method:

```julia
mutable struct MyCoding <: AbstractContrasts
    ...
end

contrasts_matrix(C::MyCoding, baseind, n) = ...
termnames(C::MyCoding, levels, baseind) = ...
```

# References

Schad, D. J., Vasishth, S., Hohenstein, S., & Kliegl, R. (2020). How to
capitalize on a priori contrasts in linear (mixed) models: A tutorial. _Journal
of Memory and Language, 110_, 104038. https://doi.org/10.1016/j.jml.2019.104038


"""
abstract type AbstractContrasts end

# Contrasts + Levels (usually from data) = ContrastsMatrix
struct ContrastsMatrix{C <: AbstractContrasts, T, U}
    matrix::Matrix{Float64}
    termnames::Vector{U}
    levels::Vector{T}
    contrasts::C
    invindex::Dict{T,Int}
    function ContrastsMatrix(matrix::AbstractMatrix,
                             termnames::Vector{U},
                             levels::Vector{T},
                             contrasts::C) where {U,T,C <: AbstractContrasts}
        invindex = Dict{T,Int}(x=>i for (i,x) in enumerate(levels))
        new{C,T,U}(matrix, termnames, levels, contrasts, invindex)
    end
end

# only check equality of matrix, termnames, and levels, and that the type is the
# same for the contrasts (values are irrelevant).  This ensures that the two
# will behave identically in creating modelmatrix columns
Base.:(==)(a::ContrastsMatrix{C,T}, b::ContrastsMatrix{C,T}) where {C<:AbstractContrasts,T} =
    a.matrix == b.matrix &&
    a.termnames == b.termnames &&
    a.levels == b.levels

Base.hash(a::ContrastsMatrix{C}, h::UInt) where {C} =
    hash(C, hash(a.matrix, hash(a.termnames, hash(a.levels, h))))

"""
An instantiation of a contrast coding system for particular levels

This type is used internally for generating model matrices based on categorical
data, and **most users will not need to deal with it directly**.  Conceptually,
a `ContrastsMatrix` object stands for an instantiation of a contrast coding
*system* for a particular set of categorical *data levels*.

If levels are specified in the `AbstractContrasts`, those will be used, and likewise
for the base level (which defaults to the first level).

# Constructors

```julia
ContrastsMatrix(contrasts::AbstractContrasts, levels::AbstractVector)
ContrastsMatrix(contrasts_matrix::ContrastsMatrix, levels::AbstractVector)
```

# Arguments

* `contrasts::AbstractContrasts`: The contrast coding system to use.
* `levels::AbstractVector`: The levels to generate contrasts for.
* `contrasts_matrix::ContrastsMatrix`: Constructing a `ContrastsMatrix` from
  another will check that the levels match.  This is used, for example, in
  constructing a model matrix from a `ModelFrame` using different data.

"""
function ContrastsMatrix(contrasts::C, levels::AbstractVector{T}) where {C<:AbstractContrasts, T}

    # if levels are defined on contrasts, use those, validating that they line up.
    # what does that mean? either:
    #
    # 1. contrasts.levels == levels (best case)
    # 2. data levels missing from contrast: would generate empty/undefined rows.
    #    better to filter data frame first
    # 3. contrast levels missing from data: would have empty columns, generate a
    #    rank-deficient model matrix.
    c_levels = something(contrasts.levels, levels)
    if eltype(c_levels) != eltype(levels)
        throw(ArgumentError("mismatching levels types: got $(eltype(levels)), expected " *
                            "$(eltype(c_levels)) based on contrasts levels."))
    end
    mismatched_levels = symdiff(c_levels, levels)
    if !isempty(mismatched_levels)
        throw(ArgumentError("contrasts levels not found in data or vice-versa: " *
                            "$mismatched_levels." *
                            "\n  Data levels: $levels." *
                            "\n  Contrast levels: $c_levels"))
    end

    n = length(c_levels)
    if n == 0
        throw(ArgumentError("empty set of levels found (need at least two to compute " *
                            "contrasts)."))
    elseif n == 1
        throw(ArgumentError("only one level found: $(c_levels[1]) (need at least two to " *
                            "compute contrasts)."))
    end

    # find index of base level. use contrasts.base, then default (1).
    base_level = baselevel(contrasts)
    baseind = base_level === nothing ?
              1 :
              findfirst(isequal(base_level), c_levels)
    if baseind === nothing
        throw(ArgumentError("base level $(base_level) not found in levels " *
                            "$c_levels."))
    end

    tnames = termnames(contrasts, c_levels, baseind)

    mat = contrasts_matrix(contrasts, baseind, n)

    ContrastsMatrix(mat, tnames, c_levels, contrasts)
end

ContrastsMatrix(c::Type{<:AbstractContrasts}, levels::AbstractVector) =
    throw(ArgumentError("contrast types must be instantiated (use $c() instead of $c)"))

# given an existing ContrastsMatrix, check that all passed levels are present
# in the contrasts. Note that this behavior is different from the
# ContrastsMatrix constructor, which requires that the levels be exactly the same.
# This method exists to support things like `predict` that can operate on new data
# which may contain only a subset of the original data's levels. Checking here
# (instead of in `modelmat_cols`) allows an informative error message.
function ContrastsMatrix(c::ContrastsMatrix, levels::AbstractVector)
    if !isempty(setdiff(levels, c.levels))
         throw(ArgumentError("there are levels in data that are not in ContrastsMatrix: " *
                             "$(setdiff(levels, c.levels))" *
                             "\n  Data levels: $(levels)" *
                             "\n  Contrast levels: $(c.levels)"))
    end
    return c
end

function termnames(C::AbstractContrasts, levels::AbstractVector, baseind::Integer)
    not_base = [1:(baseind-1); (baseind+1):length(levels)]
    levels[not_base]
end

Base.getindex(contrasts::ContrastsMatrix{C,T}, rowinds, colinds) where {C,T} =
    getindex(contrasts.matrix, getindex.(Ref(contrasts.invindex), rowinds), colinds)

# Making a contrast type T only requires that there be a method for
# contrasts_matrix(T,  baseind, n) and optionally termnames(T, levels, baseind)
# The rest is boilerplate.
for contrastType in [:DummyCoding, :EffectsCoding, :HelmertCoding, :SeqDiffCoding]
    @eval begin
        mutable struct $contrastType <: AbstractContrasts
            base::Any
            levels::Union{Vector,Nothing}
        end
        ## constructor with optional keyword arguments, defaulting to nothing
        $contrastType(; base=nothing, levels=nothing) = $contrastType(base, levels)
    end
end

baselevel(c::C) where {C<:AbstractContrasts} = :base ∈ fieldnames(C) ? c.base : nothing

"""
    FullDummyCoding()

Full-rank dummy coding generates one indicator (1 or 0) column for each level,
**including** the base level. This is sometimes known as 
[one-hot encoding](https://en.wikipedia.org/wiki/One-hot).

Not exported but included here for the sake of completeness.
Needed internally for some situations where a categorical variable with ``k``
levels needs to be converted into ``k`` model matrix columns instead of the
standard ``k-1``.  This occurs when there are missing lower-order terms, as in
discussed below in [Categorical variables in Formulas](@ref).

# Examples

```julia
julia> StatsModels.ContrastsMatrix(StatsModels.FullDummyCoding(), ["a", "b", "c", "d"]).matrix
4×4 Array{Float64,2}:
 1.0  0.0  0.0  0.0
 0.0  1.0  0.0  0.0
 0.0  0.0  1.0  0.0
 0.0  0.0  0.0  1.0
```
"""
mutable struct FullDummyCoding <: AbstractContrasts
# Dummy contrasts have no base level (since all levels produce a column)
end

ContrastsMatrix(C::FullDummyCoding, levels::AbstractVector{T}) where {T} =
    ContrastsMatrix(Matrix(1.0I, length(levels), length(levels)), levels, levels, C)

"Promote contrasts matrix to full rank version"
Base.convert(::Type{ContrastsMatrix{FullDummyCoding}}, C::ContrastsMatrix) =
    ContrastsMatrix(FullDummyCoding(), C.levels)

"""
    DummyCoding([base[, levels]])
    DummyCoding(; base=nothing, levels=nothing)

Dummy coding generates one indicator column (1 or 0) for each non-base level.

If `levels` are omitted or `nothing`, they are determined from the data using
`levels()` when constructing `Contrastsmatrix`.  If `base` is omitted or
`nothing`, the first level is used as the base.

Columns have non-zero mean and are collinear with an intercept column (and
lower-order columns for interactions) but are orthogonal to each other. In a
regression model, dummy coding leads to an intercept that is the mean of the
dependent variable for base level.

Also known as "treatment coding" or "one-hot encoding".

# Examples

```julia
julia> StatsModels.ContrastsMatrix(DummyCoding(), ["a", "b", "c", "d"]).matrix
4×3 Array{Float64,2}:
 0.0  0.0  0.0
 1.0  0.0  0.0
 0.0  1.0  0.0
 0.0  0.0  1.0
```
"""
DummyCoding

contrasts_matrix(C::DummyCoding, baseind, n) =
    Matrix(1.0I, n, n)[:, [1:(baseind-1); (baseind+1):n]]


"""
    EffectsCoding([base[, levels]])
    EffectsCoding(; base=nothing, levels=nothing)

Effects coding generates columns that code each non-base level as the
deviation from the base level.  For each non-base level `x` of `variable`, a
column is generated with 1 where `variable .== x` and -1 where `variable .== base`.

`EffectsCoding` is like `DummyCoding`, but using -1 for the base level instead
of 0.

If `levels` are omitted or `nothing`, they are determined from the data using
`levels()` when constructing `Contrastsmatrix`.  If `base` is omitted or
`nothing`, the first level is used as the base.

When all levels are equally frequent, effects coding generates model matrix
columns that are mean centered (have mean 0).  For more than two levels the
generated columns are not orthogonal.  In a regression model with an
effects-coded variable, the intercept corresponds to the grand mean.

Also known as "sum coding" or "simple coding". Note
though that the default in R and SPSS is to use the *last* level as the base.
Here we use the *first* level as the base, for consistency with other coding
systems.

# Examples

```julia
julia> StatsModels.ContrastsMatrix(EffectsCoding(), ["a", "b", "c", "d"]).matrix
4×3 Array{Float64,2}:
 -1.0  -1.0  -1.0
  1.0   0.0   0.0
  0.0   1.0   0.0
  0.0   0.0   1.0
```

"""
EffectsCoding

function contrasts_matrix(C::EffectsCoding, baseind, n)
    not_base = [1:(baseind-1); (baseind+1):n]
    mat = Matrix(1.0I, n, n)[:, not_base]
    mat[baseind, :] .= -1
    return mat
end

"""
    HelmertCoding([base[, levels]])
    HelmertCoding(; base=nothing, levels=nothing)

Helmert coding codes each level as the difference from the average of the lower
levels.

If `levels` are omitted or `nothing`, they are determined from the data using
`levels()` when constructing `Contrastsmatrix`.  If `base` is omitted or
`nothing`, the first level is used as the base.

For each non-base level, Helmert coding generates a columns with -1 for each of
n levels below, n for that level, and 0 above.

When all levels are equally frequent, Helmert coding generates columns that are
mean-centered (mean 0) and orthogonal.

# Examples

```julia
julia> StatsModels.ContrastsMatrix(HelmertCoding(), ["a", "b", "c", "d"]).matrix
4×3 Array{Float64,2}:
 -1.0  -1.0  -1.0
  1.0  -1.0  -1.0
  0.0   2.0  -1.0
  0.0   0.0   3.0
```
"""
HelmertCoding

function contrasts_matrix(C::HelmertCoding, baseind, n)
    mat = zeros(n, n-1)
    for i in 1:n-1
        mat[1:i, i] .= -1
        mat[i+1, i] = i
    end

    # re-shuffle the rows such that base is the all -1.0 row (currently first)
    mat = mat[[baseind; 1:(baseind-1); (baseind+1):end], :]
    return mat
end

"""
    SeqDiffCoding([base[, levels]])

Code each level in order to test "sequential difference" hypotheses, which
compares each level to the level below it (starting with the second level).
Specifically, the ``n``th predictor tests the hypothesis that the difference
between levels ``n`` and ``n+1`` is zero.

Differences are computed in order of `levels`.  If `levels` are omitted or
`nothing`, they are determined from the data using `levels()` when constructing
`Contrastsmatrix`.  If `base` is omitted or `nothing`, the first level is used
as the base.

# Examples

```jldoctest seqdiff
julia> seqdiff = StatsModels.ContrastsMatrix(SeqDiffCoding(), ["a", "b", "c", "d"]).matrix
4×3 Array{Float64,2}:
 -0.75  -0.5  -0.25
  0.25  -0.5  -0.25
  0.25   0.5  -0.25
  0.25   0.5   0.75
```

The interpretation of sequential difference coding may be hard to see from the
contrasts matrix itself.  The corresponding hypothesis matrix shows a clearer
picture.  From the rows of the hypothesis matrix, we can see that these
contrasts test the difference between the first and second levels, the second
and third, and the third and fourth, respectively:

```jldoctest seqdiff
julia> round.(pinv(seqdiff), digits=2)
3×4 Array{Float64,2}:
 -1.0   1.0  -0.0   0.0
 -0.0  -1.0   1.0  -0.0
  0.0  -0.0  -1.0   1.0
```

"""
SeqDiffCoding

function contrasts_matrix(C::SeqDiffCoding, baseind, n)
    mat = zeros(n, n-1)
    for col in 1:n-1
        mat[1:col, col] .= col-n
        mat[col+1:end, col] .= col
    end
    return mat ./ n
end


"""
    HypothesisCoding(hypotheses::AbstractMatrix; levels=nothing, labels=nothing)

Specify how to code a categorical variable in terms of a *hypothesis matrix*.
For a variable with ``k`` levels, this should be a ``k-1 \times k`` matrix.
Each row of the matrix corresponds to a hypothesis about the mean
outcomes under each of the ``k`` levels of the predictor.  The entries in the
row give the weights assigned to each of these ``k`` means, and the
corresponding predictor in a regression model estimates the weighted sum of
these cell means.

For instance, if we have a variable which has four levels A, B, C, and D, and we
want to test the hypothesis that the difference between the average outcomes for
levels A and B is different from zero, the corresponding row of the hypothesis
matrix would be `[-1, 1, 0, 0]`.  Likewise, to test whether the difference
between B and C is different from zero, the hypothesis vector would be `[0, -1,
1, 0]`.  To test each "successive difference" hypothesis, the full hypothesis
matrix would be

```jldoctest hyp
julia> sdiff_hypothesis = [-1  1  0  0
                            0 -1  1  0
                            0  0 -1  1];
```

Contrasts are derived the hypothesis matrix by taking the pseudoinverse:

```jldoctest hyp
julia> sdiff_contrasts = pinv(sdiff_hypothesis)
4×3 Array{Float64,2}:
 -0.75  -0.5  -0.25
  0.25  -0.5  -0.25
  0.25   0.5  -0.25
  0.25   0.5   0.75
```

The above matrix is what is produced by constructing a [`ContrastsMatrix`](@ref) from a
`HypothesisCoding` instance:

```jldoctest hyp
julia> StatsModels.ContrastsMatrix(HypothesisCoding(sdiff_hypothesis), ["a", "b", "c", "d"]).matrix
4×3 Array{Float64,2}:
 -0.75  -0.5  -0.25
  0.25  -0.5  -0.25
  0.25   0.5  -0.25
  0.25   0.5   0.75
```

The interpretation of the such "sequential difference" contrasts are clear when
expressed as a hypothesis matrix, but it is not obvious just from looking at the
contrasts matrix.  For this reason `HypothesisCoding` is preferred for
specifying custom contrast coding schemes over `ContrastsCoding`.

Optional arguments `levels` and `labels` give the names (in order) of the
hypothesis matrix columns (corresponding to levels of the data) and rows
(corresponding to the tested hypothesis).  The `labels` also determine the names
of the model matrix columns generated by these contrasts,

# References

Schad, D. J., Vasishth, S., Hohenstein, S., & Kliegl, R. (2020). How to
capitalize on a priori contrasts in linear (mixed) models: A tutorial. _Journal
of Memory and Language, 110_, 104038. https://doi.org/10.1016/j.jml.2019.104038

"""
mutable struct HypothesisCoding{T<:AbstractMatrix, S<:AbstractMatrix} <: AbstractContrasts
    hypotheses::T
    contrasts::S
    levels::Union{AbstractVector,Nothing}
    labels::Union{AbstractVector,Nothing}

    function HypothesisCoding(hypotheses::T, levels, labels) where {T}
        labels == nothing && 
            Base.depwarn(
                "HypothesisCoding without specified contrast labels is deprecated.  " *
                "Specify contrast labels with `HypothesisCoding(; labels=[...])` " *
                "or HypothesisCoding(Dict(label1=>hyp1, label2=>hyp2, ...))",
                :HypothesisCoding)
        contrasts = pinv(hypotheses)
        S = typeof(contrasts)
        check_contrasts_size(contrasts, levels)
        new{T,S}(hypotheses, contrasts, levels, labels)
    end
end

HypothesisCoding(mat::AbstractMatrix; levels=nothing, labels=nothing) =
    HypothesisCoding(mat, levels, labels)

"""
    HypothesisCoding(hypotheses::Dict[; labels=collect(keys(hypotheses)), levels=nothing])

Specify hypotheses as `label=>hypothesis_vector` pairs.  If labels are specified
via keyword argument, the hypothesis vectors will be concatenated in that order.
The `levels` argument provides the names of the levels for each entry in the
hypothesis vectors.  If omitted, `levels()` will be called when constructing a 
`ContrastsMatrix`
"""
function HypothesisCoding(hypotheses::Dict{<:Any,<:AbstractVector};
                          labels=collect(keys(hypotheses)),
                          levels=nothing)
    !isempty(symdiff(keys(hypotheses), labels)) &&
        throw(ArgumentError("mismatching labels between hypotheses and labels keyword argument: " *
                            "$(join(symdiff(keys(hypotheses), labels), ", "))"))
    
    mat = reduce(hcat, collect(hypotheses[label] for label in labels))'
    HypothesisCoding(mat; labels=labels, levels=levels)
end


function contrasts_matrix(C::HypothesisCoding, baseind, n)
    check_contrasts_size(C.contrasts, n)
    C.contrasts
end

termnames(C::HypothesisCoding, levels::AbstractVector, baseind::Int) =
    something(C.labels, levels[1:length(levels) .!= baseind])

"""
    StatsModels.ContrastsCoding(mat::AbstractMatrix[, levels]])
    StatsModels.ContrastsCoding(mat::AbstractMatrix[; levels=nothing])

Coding by manual specification of contrasts matrix. For k levels, the contrasts
must be a k by k-1 Matrix.  The contrasts in this matrix will be copied directly
into the model matrix; if you want to specify your contrasts as hypotheses (i.e., 
weights assigned to each level's cell mean), you should use 
[`HypothesisCoding`](@ref) instead.
"""
mutable struct ContrastsCoding{T<:AbstractMatrix} <: AbstractContrasts
    mat::T
    levels::Union{Vector,Nothing}

    function ContrastsCoding(mat::T, levels) where {T<:AbstractMatrix}
        Base.depwarn("`ContrastsCoding(contrasts)` is deprecated and will not be" *
                     " exported in the future.  Future versions will require" *
                     " `StatsModels.ContrastsCoding` or `using StatsModels: " *
                     "ContrastsCoding`.  For general users we recommend " *
                     "`HypothesisCoding(pinv(contrasts))` instead.", 
                     :ContrastsCoding)
        check_contrasts_size(mat, levels)
        new{T}(mat, levels)
    end
end

check_contrasts_size(mat::Matrix, ::Nothing) = check_contrasts_size(mat, size(mat,1))
check_contrasts_size(mat::Matrix, levels::Vector) = check_contrasts_size(mat, length(levels))
check_contrasts_size(mat::Matrix, n_lev::Int) =
    size(mat) == (n_lev, n_lev-1) ||
    throw(ArgumentError("contrasts matrix wrong size for $n_lev levels. " *
                        "Expected $((n_lev, n_lev-1)), got $(size(mat))"))

## constructor with optional keyword arguments, defaulting to nothing
ContrastsCoding(mat::AbstractMatrix; levels=nothing) =
    ContrastsCoding(mat, levels)

function contrasts_matrix(C::ContrastsCoding, baseind, n)
    check_contrasts_size(C.mat, n)
    C.mat
end

## hypothesis matrix
"""
    needs_intercept(mat::AbstractMatrix)

Returns `true` if a contrasts matrix `mat` needs to consider the intercept to
determine the corresponding hypothesis matrix.  This is determined by whether
`rank(mat)` is less than the number of rows and any column is not orthogonal to
the intercept column.
"""
needs_intercept(mat::AbstractMatrix) =
    (rank(mat) < size(mat, 1)) &&
    !all(isapprox(sum(col), zero(eltype(mat)), rtol=1e-5) for col in eachcol(mat))

"""
    hypothesis_matrix(cmat::AbstractMatrix; intercept=needs_intercept(cm), pretty=true)
    hypothesis_matrix(contrasts::AbstractContrasts, n; baseind=1, kwargs...)
    hypothesis_matrix(cmat::ContrastsMatrix; kwargs...)

Compute the hypotehsis matrix for a contrasts matrix using the generalized
pseudo-inverse (`LinearAlgebra.pinv`).  `intercept` determines whether a column
of ones is included before taking the pseudoinverse, which is needed for
contrasts where the columns are not orthogonal to the intercept (e.g., have
non-zero mean).  If `pretty=true` (the default), the hypotheses are rounded to
`Int`s if possible and `Rational`s if not, using a tolerance of `1e-10`.

Note that this assumes a *balanced design* where there are the same number of
observations in every cell.  This is only important for non-orthgonal contrasts
(including contrasts where the contrasts are not orthogonal with the intercept).

# Examples

```jldoctest
julia> cmat = StatsModels.contrasts_matrix(DummyCoding(), 1, 4)
4×3 Array{Float64,2}:
 0.0  0.0  0.0
 1.0  0.0  0.0
 0.0  1.0  0.0
 0.0  0.0  1.0

julia> StatsModels.hypothesis_matrix(cmat)
4×4 Array{Int64,2}:
 1  -1  -1  -1
 0   1   0   0
 0   0   1   0
 0   0   0   1

julia> StatsModels.hypothesis_matrix(cmat, intercept=false) # wrong without intercept!!
4×3 Array{Int64,2}:
 0  0  0
 1  0  0
 0  1  0
 0  0  1

julia> StatsModels.hypothesis_matrix(cmat, pretty=false) # ugly
4×4 Adjoint{Float64,Array{Float64,2}}:
  1.0          -1.0          -1.0          -1.0        
 -2.23753e-16   1.0           4.94472e-17   1.04958e-16
  6.91749e-18  -2.42066e-16   1.0          -1.31044e-16
 -1.31485e-16   9.93754e-17   9.93754e-17   1.0        

julia> StatsModels.hypothesis_matrix(StatsModels.ContrastsMatrix(DummyCoding(), ["a", "b", "c", "d"]))
4×4 Array{Int64,2}:
 1  -1  -1  -1
 0   1   0   0
 0   0   1   0
 0   0   0   1

```
"""
function hypothesis_matrix(cm::AbstractMatrix; intercept=needs_intercept(cm), pretty=true)
    if intercept
        cm = hcat(ones(size(cm, 1)), cm)
    end
    hypotheses = pinv(cm)
    pretty ? pretty_mat(hypotheses) : hypotheses
end

hypothesis_matrix(contrasts::AbstractContrasts, n; baseind=1, kwargs...) =
    hypothesis_matrix(contrasts_matrix(contrasts, baseind, n); kwargs...)

hypothesis_matrix(cmat::ContrastsMatrix; kwargs...) =
    hypothesis_matrix(cmat.matrix; kwargs...)

function pretty_mat(mat::AbstractMatrix; tol=10*eps(eltype(mat)))
    fracs = rationalize.(mat, tol=tol)
    if all(denominator.(fracs) .== 1)
        return Int.(fracs)
    else
        return fracs
    end
end
    
