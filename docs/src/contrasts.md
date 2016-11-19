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
contrasts are appropriate for a categorical variable with $k$ levels when it
*aliases* other terms, making it *partially redundant*.  Using rank-$k$ for such
a redundant variable will generally result in a rank-deficient model matrix and
a model that can't be identified.

A categorical variable in a term *aliases* the term that remains when that
variable is dropped.  For example, with categorical `a`:

* In `a`, the sole variable `a` aliases the intercept term `1`.
* In `a&b`, the variable `a` aliases the main effect term `b`, and vice versa.
* In `a&b&c`, the variable `a` alises the interaction term `b&c` (regardless of
  whether `b` and `c` are categorical).

If a categorical variable aliases another term that is present elsewhere in the
formula, we call that variable *redundant*.  A variable is *non-redundant* when
the term that it alises is _not_ present elsewhere in the formula.  For
categorical `a`, `b`, and `c`:

* In `y ~ 1 + a`, the `a` in the main effect of `a` aliases the intercept `1`.
* In `y ~ 0 + a`, `a` does not alias any other terms and is *non-redundant*.
* In `y ~ 1 + a + a&b`:
    * The `b` in `a&b` is redundant because it aliases the main effect `a`:
      dropping `b` from `a&b` leaves `a`.
    * The `a` in `a&b` is *non-redundant* because it aliases `b`, which is not
      present anywhere else in the formula.

When constructing a `ModelFrame` from a `Formula`, each term is checked for
non-redundant categorical variables.  Any such non-redundant variables are
"promoted" to full rank in that term by using [`FullDummyCoding`](@ref) instead
of the contrasts used elsewhere for that variable.

One additional complexity is introduced by promoting non-redundant variables to
full rank.  For the purpose of determining redundancy, a full-rank dummy coded
categorical variable _implicitly_ introduces the term that it aliases into the
formula.  Thus, in `y ~ 1 + a + a&b + b&c`:

* In `a&b`, `a` aliases the main effect `b`, which is not explicitly present in
  the formula.  This makes it non-redundant and so its contrast coding is
  promoted to `FullDummyCoding`, which _implicitly_ introduces the main effect
  of `b`.
* Then, in `b&c`, the variable `c` is now _redundant_ because it aliases the main
  effect of `b`, and so it keeps its original contrast coding system.
