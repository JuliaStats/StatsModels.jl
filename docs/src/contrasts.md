```@meta
CurrentModule = StatsModels
```

# Modeling categorical data

To convert categorical data into a numerical representation suitable for
modeling, `StatsModels` implements a variety of __contrast coding strategies__.
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

## Further details

### Categorical variables in `Formula`s

Generating model matrices from multiple variables, some of which are
categorical, requires special care.  The reason for this is that rank-$k-1$
contrasts are appropriate for a categorical variable with $k$ levels when it is
_redundant_ with lower-order terms: using rank-$k$ will often result in a
rank-deficient model matrix which leads to a model that can't be identified.  A
categorical variable in a term is _redundant_ when the term obtained by dropping
that variable is identical to a term already present in the
formula.[^implicit-terms]

For example: 
* In `y ~ 1 + x`, `x` is redundant with the intercept `1`.
* In `y ~ 0 + x`, `x` is _non-redundant_ with any other terms.
* In `y ~ 1 + x + x&y`:
    * The `y` in `x&y` is redundant, because dropping `y` from `x&y` leaves `x`,
      which is included in the formula
    * The `x` in `x&y` is _non-redundant_: dropping it leaves `y`, which is not
      present anywhere else in the formula.


Additionally, when constructing a `ModelFrame` from a `Formula` combined with a
`DataFrame`, we check whether any categorical variables that occur in the
formula are _non-redundant_ with other, lower-order terms.  For instance, the
term `x` in `y ~ 1 + x` is redundant with the intercept term `1`, but in 
`y ~ 0 + x` is non-redundant: using the default rank $k-1$ contrasts matrix will
result in a non-fully-specified model. 

Any such non-redundant categorical terms need to be promoted to full-rank
contrasts, with one indicator column per level.


[^implicit-terms]: This includes implicit terms that result from promoting
    another categorical variable to full-rank.
