# StatsModels Documentation

This package provides common abstractions and utilities for specifying, fitting,
and evaluating statistical models.  The goal is to provide an API for package
developers implementing different kinds of statistical models (see
the [GLM](https://www.github.com/JuliaStats/GLM.jl) package
for example), and utilities that are generally useful for both users and
developers when dealing with statistical models and tabular data.

* Formula notation for specifying models based on tabular data

    * `Formula`
    * `ModelFrame`
    * `ModelMatrix`

* Contrast coding for categorical data

* Abstract model types

    * `StatisticalModel`
    * `RegressionModel`

Much of this package was formerly part
of [`DataTables`](https://www.github.com/JuliaStats/DataTables.jl)
and [`StatsBase`](https://www.github.com/JuliaStats/StatsBase.jl).
