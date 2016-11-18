```@meta
CurrentModule = StatsModels
```

# Modeling categorical data

To convert categorical data into a numerical representation suitable for
modeling, `StatsModels` implements a variety of **contrast coding strategies**.
Each contrast coding strategy maps a categorical vector with $k$ levels onto
$k-1$ linearly independent model matrix columns.

## How to specify contrast coding

The default contrast coding strategy is `DummyCoding`.  To override this, use
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

## Contrast coding strategies

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
*redundant* with lower-order terms: using rank-$k$ will often result in a
rank-deficient model matrix which leads to a model that can't be identified.  A
categorical variable in a term is *redundant* when the term obtained by dropping
that variable is identical to a term already present in the
formula.[^implicit-terms]

For example: 
* In `y ~ 1 + x`, `x` is redundant with the intercept `1`.
* In `y ~ 0 + x`, `x` is *non-redundant* with any other terms.
* In `y ~ 1 + x + x&y`:
    * The `y` in `x&y` is redundant, because dropping `y` from `x&y` leaves `x`,
      which is included in the formula
    * The `x` in `x&y` is *non-redundant*: dropping it leaves `y`, which is not
      present anywhere else in the formula.

When constructing a `ModelFrame` from a `Formula`, each term is checked for
non-redundant categorical variables.  Any such non-redundant variables are
"promoted" to full rank in that term by using [`FullDummyCoding`](@ref) instead
of the contrasts used elsewhere for that variable.

[^implicit-terms]: This includes implicit terms that result from promoting
    another categorical variable to full-rank.
