```@meta
CurrentModule = StatsModels
```

# Modeling categorical data

To convert categorical data into a numerical representation suitable for
modeling, `StatsModels` implements a variety of **contrast coding systems**.
Each contrast coding system maps a categorical vector with $k$ levels onto
$k-1$ linearly independent model matrix columns.

The following contrast coding systems are implemented:

* [`DummyCoding`](@ref)
* [`EffectsCoding`](@ref)
* [`HelmertCoding`](@ref)
* [`ContrastsCoding`](@ref)

## How to specify contrast coding

The default contrast coding system is `DummyCoding`.  To override this, use
the `contrasts` argument when constructing a `ModelFrame`:

```julia
mf = ModelFrame(y ~ 1 + x, df, contrasts = Dict(:x => EffectsCoding()))
```

To change the contrast coding for one or more variables in place, use

```@docs
setcontrasts!
```

## Interface

```@docs
AbstractContrasts
ContrastsMatrix
```

## Contrast coding systems

```@docs
DummyCoding
EffectsCoding
HelmertCoding
ContrastsCoding
```

### Special internal contrasts

```@docs
FullDummyCoding
```

## Further details

### Categorical variables in `Formula`s

Generating model matrices from multiple variables, some of which are
categorical, requires special care.  The reason for this is that rank-$k-1$
contrasts are appropriate for a categorical variable with $k$ levels when it is
*redundant* with other terms: using rank-$k$ will generally result in a
rank-deficient model matrix and a model that can't be identified.

A categorical variable in a term is *redundant* when dropping that variable from
the term results in a term that is present elsewhere in the formula.  For
example, with categorical `a`, `b`, and `c`:

* In `y ~ 1 + a`, `a` is redundant with the intercept `1`.
* In `y ~ 0 + a`, `a` is *non-redundant* with any other terms.
* In `y ~ 1 + a + a&b`:
    * The `b` in `a&b` is redundant, because dropping `b` from `a&b` leaves `a`,
      which is included in the formula
    * The `a` in `a&b` is *non-redundant*: dropping it leaves `b`, which is not
      present anywhere else in the formula.

When constructing a `ModelFrame` from a `Formula`, each term is checked for
non-redundant categorical variables.  Any such non-redundant variables are
"promoted" to full rank in that term by using [`FullDummyCoding`](@ref) instead
of the contrasts used elsewhere for that variable.
