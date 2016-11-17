## Modeling tabular data

Most statistical models require that data be represented as a Matrix-like
collection of a single numeric type.  Much of the data we want to model,
however, is __tabular data__, where data is represented as a collection of
fields with possibly heterogeneous types.  One of the primary goals of
`StatsModels` is to make it simpler to transform tabular data into matrix format
suitable for statistical modeling.

### The `Formula` type

The basic conceptual tool for this is the `Formula`, which has a left side and a
right side, separated by `~`:

```julia
f = y ~ 1 + x
```

The left side of a formula conventionally represents _dependent_ variables, and
the right side _independent_ variables (or regressors).  _Terms_ are separated
by `+`.  Basic terms are the integers `1` or `0`---evaluated as the presence or
absence of a constant intercept term, respectively---and variables like `x`,
which will evaluate to the data source column with that name as a symbol (`:x`).

Individual variables can be combined into _interaction terms_ with `&`, as in
`x&z`, which will evaluate to the product of the columns named `:x` and `:z`.
Because it's often convenient to include main effects and interactions for a
number of variables, the `*` operator will expand in this way

```julia
y ~ 1 + x*y = y ~ 1 + x + y + x&y
```

This applies to higher-order interactions, too: `x*y*z` expands to the main
effects, all two-way interactions, and the three way interaction `x&y&z`.

### The `ModelFrame` and `ModelMatrix` types

This package supplies `fit` methods for statistical models that take a `Formula`
and `DataFrame`.  Internally, these methods use the `ModelFrame` and
`ModelMatrix` types to create the numeric input these models require.  These
types are exposed in case you want to use them for other purposes.

The `ModelFrame` type is a wrapper that combines a `Formula` and a `DataFrame`:

```julia
mf = ModelFrame(y ~ 1 + x, df)
```

This wrapper encapsulates all the information that's required to transform data
of the same structure as the wrapped `DataFrame` into a model matrix.  This goes
above and beyond what's expressed in the `Formula` itself, for instance
including information on each categorical variable should be coded (see below).

The `ModelMatrix` type actually constructs a matrix suitable for modeling.

```julia
mm = ModelMatrix(ModelFrame(y ~ 1 + x, df))
```
