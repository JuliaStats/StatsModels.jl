# StatsModels Documentation

This package provides common abstractions and utilities for specifying, fitting,
and evaluating statistical models.  The goal is to provide an API for package
developers implementing different kinds of statistical models (see
the [GLM](https://www.github.com/JuliaStats/GLM.jl) package
for example), and utilities that are generally useful for both users and
developers when dealing with statistical models and tabular data.

* [Formula notation](@ref Modeling-tabular-data) for transforming tabular data
  into numerical arrays for modeling.
* Mechanisms for [extending the `@formula` notation](@ref
  Internals-and-extending-the-formula-DSL) in external modeling packages.
* [Contrast coding](@ref Modeling-categorical-data) for categorical data
* Types and [API](@ref Modeling) for fitting and working with statistical
  models, extending [StatsBase.jl's
  API](http://juliastats.github.io/StatsBase.jl/stable/statmodels.html) to
  tabular data.

!!! note

    Much of this package was formerly part
    of [DataFrames.jl](https://www.github.com/JuliaStats/DataFrames.jl) and
    historically only handled tabular data in the form of a `DataFrame`, but
    currently supports any table that supports the minimal
    [Tables.jl](https://github.com/JuliaData/Tables.jl/) interface.  It's thus a
    relatively light dependency.
