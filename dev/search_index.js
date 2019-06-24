var documenterSearchIndex = {"docs": [

{
    "location": "#",
    "page": "Introduction",
    "title": "Introduction",
    "category": "page",
    "text": ""
},

{
    "location": "#StatsModels-Documentation-1",
    "page": "Introduction",
    "title": "StatsModels Documentation",
    "category": "section",
    "text": "This package provides common abstractions and utilities for specifying, fitting, and evaluating statistical models.  The goal is to provide an API for package developers implementing different kinds of statistical models (see the GLM package for example), and utilities that are generally useful for both users and developers when dealing with statistical models and tabular data.Formula notation for transforming tabular data into numerical arrays for modeling.\nMechanisms for extending the @formula notation in external modeling packages.\nContrast coding for categorical data\nTypes and API for fitting and working with statistical models, extending StatsBase.jl\'s API to tabular data.note: Note\nMuch of this package was formerly part of DataFrames.jl and historically only handled tabular data in the form of a DataFrame, but currently supports any table that supports the minimal Tables.jl interface.  It\'s thus a relatively light dependency."
},

{
    "location": "formula/#",
    "page": "Modeling tabular data",
    "title": "Modeling tabular data",
    "category": "page",
    "text": "CurrentModule = StatsModels\nDocTestSetup = quote\n    using StatsModels\n    using Random\n    Random.seed!(1)\nend"
},

{
    "location": "formula/#Modeling-tabular-data-1",
    "page": "Modeling tabular data",
    "title": "Modeling tabular data",
    "category": "section",
    "text": "Most statistical models require that data be represented as a Matrix-like collection of a single numeric type.  Much of the data we want to model, however, is tabular data, where data is represented as a collection of fields with possibly heterogeneous types.  One of the primary goals of StatsModels is to make it simpler to transform tabular data into matrix format suitable for statistical modeling.At the moment, \"tabular data\" means a Tables.jl table, which will be materialized as a Tables.ColumnTable (a NamedTuple of column vectors).  Work on first-class support for streaming/row-oriented tables is ongoing."
},

{
    "location": "formula/#The-@formula-language-1",
    "page": "Modeling tabular data",
    "title": "The @formula language",
    "category": "section",
    "text": "StatsModels implements the @formula domain-specific language for describing table-to-matrix transformations.  This language is designed to be familiar to users of other statistical software, while also taking advantage of Julia\'s unique strengths to be fast and flexible.A basic formula is composed of individual terms—symbols which refer to data columns, or literal numbers 0 or 1—combined by +, &, *, and (at the top level) ~.note: Note\nThe @formula macro must be called with parentheses to ensure that the formula is parsed properly.Here is an example of the @formula in action:julia> using StatsModels, DataFrames\n\njulia> f = @formula(y ~ 1 + a + b + c + b&c)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n  c(unknown)\n  b(unknown) & c(unknown)\n\njulia> df = DataFrame(y = rand(9), a = 1:9, b = rand(9), c = repeat([\"d\",\"e\",\"f\"], 3))\n9×4 DataFrame\n│ Row │ y          │ a     │ b         │ c      │\n│     │ Float64    │ Int64 │ Float64   │ String │\n├─────┼────────────┼───────┼───────────┼────────┤\n│ 1   │ 0.236033   │ 1     │ 0.986666  │ d      │\n│ 2   │ 0.346517   │ 2     │ 0.555751  │ e      │\n│ 3   │ 0.312707   │ 3     │ 0.437108  │ f      │\n│ 4   │ 0.00790928 │ 4     │ 0.424718  │ d      │\n│ 5   │ 0.488613   │ 5     │ 0.773223  │ e      │\n│ 6   │ 0.210968   │ 6     │ 0.28119   │ f      │\n│ 7   │ 0.951916   │ 7     │ 0.209472  │ d      │\n│ 8   │ 0.999905   │ 8     │ 0.251379  │ e      │\n│ 9   │ 0.251662   │ 9     │ 0.0203749 │ f      │\n\njulia> f = apply_schema(f, schema(f, df))\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  1\n  a(continuous)\n  b(continuous)\n  c(DummyCoding:3→2)\n  b(continuous) & c(DummyCoding:3→2)\n\njulia> resp, pred = modelcols(f, df);\n\njulia> pred\n9×7 Array{Float64,2}:\n 1.0  1.0  0.986666   0.0  0.0  0.0       0.0\n 1.0  2.0  0.555751   1.0  0.0  0.555751  0.0\n 1.0  3.0  0.437108   0.0  1.0  0.0       0.437108\n 1.0  4.0  0.424718   0.0  0.0  0.0       0.0\n 1.0  5.0  0.773223   1.0  0.0  0.773223  0.0\n 1.0  6.0  0.28119    0.0  1.0  0.0       0.28119\n 1.0  7.0  0.209472   0.0  0.0  0.0       0.0\n 1.0  8.0  0.251379   1.0  0.0  0.251379  0.0\n 1.0  9.0  0.0203749  0.0  1.0  0.0       0.0203749\n\njulia> coefnames(f)\n(\"y\", [\"(Intercept)\", \"a\", \"b\", \"c: e\", \"c: f\", \"b & c: e\", \"b & c: f\"])\nLet\'s break down the formula expression y ~ 1 + a + b + c + b&c:At the top level is the formula separator ~, which separates the left-hand (or response) variable y from the right-hand size (or predictor) variables on the right 1 + a + b + c + b&c.The left-hand side has one term y which means that the response variable is the column from the data named :y.  The response can be accessed with the analogous response(f, df) function.The right hand side is made up of a number of different terms, separated by +: 1 + a + b + c + b&c.  Each term corresponds to one or more columns in the generated model matrix: The first term 1 generates a constant or \"intercept\" column full of 1.0s.\nThe next two terms a and b correspond to columns from the data table called :a, :b, which both hold numeric data (Float64 and Int respectively).  By default, numerical columns are assumed to correspond to continuous terms, and are converted to Float64 and copied to the model matrix.\nThe term c corresponds to the :c column in the table, which is not numeric, so it has been contrast coded: there are three unique values or levels, and the default coding scheme (DummyCoding) generates an indicator variable for each level after the first (e.g., df[:c] .== \"b\" and df[:c] .== \"a\").\nThe last term b&c is an interaction term, and generates model matrix columns for each pair of columns generated by the b and c terms. Columns are combined with element-wise multiplication.  Since b generates only a single column and c two, b&c generates two columns, equivalent to df[:b] .* (df[:c] .== \"b\") and df[:b] .* (df[:c] .== \"c\").Because we often want to include both \"main effects\" (b and c) and interactions (b&c) of multiple variables, within a @formula the * operator denotes this \"main effects and interactions\" operation:julia> @formula(y ~ 1 + a + b*c)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n  c(unknown)\n  b(unknown) & c(unknown)Also note that the interaction operators & and * are distributive with the term separator +:julia> @formula(y ~ 1 + (a + b) & c)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown) & c(unknown)\n  b(unknown) & c(unknown)"
},

{
    "location": "formula/#Julia-functions-in-a-@formula-1",
    "page": "Modeling tabular data",
    "title": "Julia functions in a @formula",
    "category": "section",
    "text": "Any calls to Julia functions that don\'t have special meaning (or are part of an extension provided by a modeling package) are treated like normal Julia code, and evaluated elementwise:julia> modelmatrix(@formula(y ~ 1 + a + log(1+a)), df)\n9×3 Array{Float64,2}:\n 1.0  1.0  0.693147\n 1.0  2.0  1.09861\n 1.0  3.0  1.38629\n 1.0  4.0  1.60944\n 1.0  5.0  1.79176\n 1.0  6.0  1.94591\n 1.0  7.0  2.07944\n 1.0  8.0  2.19722\n 1.0  9.0  2.30259Note that the expression 1 + a is treated differently as part of the formula than in the call to log, where it\'s interpreted as normal addition.This even applies to custom functions.  For instance, if for some reason you wanted to include a regressor based on a String column that encoded whether any character in a string was after \'e\' in the alphabet, you could dojulia> gt_e(s) = any(c > \'e\' for c in s)\ngt_e (generic function with 1 method)\n\njulia> modelmatrix(@formula(y ~ 1 + gt_e(c)), df)\n9×2 Array{Float64,2}:\n 1.0  0.0\n 1.0  0.0\n 1.0  1.0\n 1.0  0.0\n 1.0  0.0\n 1.0  1.0\n 1.0  0.0\n 1.0  0.0\n 1.0  1.0\nJulia functions like this are evaluated elementwise when the numeric arrays are created for the response and model matrix.  This makes it easy to fit models to transformed data lazily, without creating temporary columns in your table. For instance, to fit a linear regression to a log-transformed response:julia> using GLM\n\njulia> lm(@formula(log(y) ~ 1 + a + b), df)\nStatsModels.TableRegressionModel{LinearModel{LmResp{Array{Float64,1}},DensePredChol{Float64,LinearAlgebra.Cholesky{Float64,Array{Float64,2}}}},Array{Float64,2}}\n\n:(log(y)) ~ 1 + a + b\n\nCoefficients:\n──────────────────────────────────────────────────────\n              Estimate  Std.Error    t value  Pr(>|t|)\n──────────────────────────────────────────────────────\n(Intercept)  -4.16168    2.98788   -1.39285     0.2131\na             0.357482   0.342126   1.04489     0.3363\nb             2.32528    3.13735    0.741159    0.4866\n──────────────────────────────────────────────────────\n\njulia> df[:log_y] = log.(df[:y]);\n\njulia> lm(@formula(log_y ~ 1 + a + b), df)            # equivalent\nStatsModels.TableRegressionModel{LinearModel{LmResp{Array{Float64,1}},DensePredChol{Float64,LinearAlgebra.Cholesky{Float64,Array{Float64,2}}}},Array{Float64,2}}\n\nlog_y ~ 1 + a + b\n\nCoefficients:\n──────────────────────────────────────────────────────\n              Estimate  Std.Error    t value  Pr(>|t|)\n──────────────────────────────────────────────────────\n(Intercept)  -4.16168    2.98788   -1.39285     0.2131\na             0.357482   0.342126   1.04489     0.3363\nb             2.32528    3.13735    0.741159    0.4866\n──────────────────────────────────────────────────────\nThe no-op function identity can be used to block the normal formula-specific interpretation of +, *, and &:julia> modelmatrix(@formula(y ~ 1 + b + identity(1+b)), df)\n9×3 Array{Float64,2}:\n 1.0  0.986666   1.98667\n 1.0  0.555751   1.55575\n 1.0  0.437108   1.43711\n 1.0  0.424718   1.42472\n 1.0  0.773223   1.77322\n 1.0  0.28119    1.28119\n 1.0  0.209472   1.20947\n 1.0  0.251379   1.25138\n 1.0  0.0203749  1.02037"
},

{
    "location": "formula/#Constructing-a-formula-programatically-1",
    "page": "Modeling tabular data",
    "title": "Constructing a formula programatically",
    "category": "section",
    "text": "A formula can be constructed at run-time by creating Terms and combining them with the formula operators +, &, and ~:julia> Term(:y) ~ ConstantTerm(1) + Term(:a) + Term(:b) + Term(:a) & Term(:b)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n  a(unknown) & b(unknown)The term function constructs a term of the appropriate type from symbols and numbers, which makes it easy to work with collections of mixed type:julia> ts = term.((1, :a, :b))\n1\na(unknown)\nb(unknown)These can then be combined with standard reduction techniques:julia> f1 = term(:y) ~ foldl(+, ts)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n\njulia> f2 = term(:y) ~ sum(ts)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n\njulia> f1 == f2 == @formula(y ~ 1 + a + b)\ntrue\n"
},

{
    "location": "formula/#Fitting-a-model-from-a-formula-1",
    "page": "Modeling tabular data",
    "title": "Fitting a model from a formula",
    "category": "section",
    "text": "The main use of @formula is to streamline specifying and fitting statistical models based on tabular data.  From the user\'s perspective, this is done by fit methods that take a FormulaTerm and a table instead of numeric matrices.As an example, we\'ll simulate some data from a linear regression model with an interaction term, a continuous predictor, a categorical predictor, and the interaction of the two, and then fit a GLM.LinearModel to recover the simulated coefficients.julia> using GLM, DataFrames, StatsModels\n\njulia> data = DataFrame(a = rand(100), b = repeat([\"d\", \"e\", \"f\", \"g\"], 25));\n\njulia> X = StatsModels.modelmatrix(@formula(y ~ 1 + a*b).rhs, data);\n\njulia> β_true = 1:8;\n\njulia> ϵ = randn(100)*0.1;\n\njulia> data[:y] = X*β_true .+ ϵ;\n\njulia> mod = fit(LinearModel, @formula(y ~ 1 + a*b), data)\nStatsModels.TableRegressionModel{LinearModel{LmResp{Array{Float64,1}},DensePredChol{Float64,LinearAlgebra.Cholesky{Float64,Array{Float64,2}}}},Array{Float64,2}}\n\ny ~ 1 + a + b + a & b\n\nCoefficients:\n───────────────────────────────────────────────────\n             Estimate  Std.Error  t value  Pr(>|t|)\n───────────────────────────────────────────────────\n(Intercept)   0.98878  0.0384341  25.7266    <1e-43\na             2.00843  0.0779388  25.7694    <1e-43\nb: e          3.03726  0.0616371  49.2764    <1e-67\nb: f          4.03909  0.0572857  70.5078    <1e-81\nb: g          5.02948  0.0587224  85.6484    <1e-88\na & b: e      5.9385   0.10753    55.2264    <1e-71\na & b: f      6.9073   0.112483   61.4075    <1e-75\na & b: g      7.93918  0.111285   71.3407    <1e-81\n───────────────────────────────────────────────────\nInternally, this is accomplished in three steps:The expression passed to @formula is lowered to term constructors combined by ~, +, and &, which evaluate to create terms for the whole formula and any interaction terms.\nA schema is extracted from the data, which determines whether each variable is continuous or categorical and extracts the summary statistics of each variable (mean/variance/min/max or unique levels respectively).  This schema is then applied to the formula with apply_schema(term, schema, ::Type{Model}), which returns a new formula with each placeholder Term replaced with a concrete ContinuousTerm or CategoricalTerm as appropriate.  This is also the stage where any custom syntax is applied (see the section on extending the @formula language for more details).\nNumeric arrays are generated for the response and predictors from the full table using modelcols(term, data).The ModelFrame and ModelMatrix types can still be used to do this transformation, but this is only to preserve some backwards compatibility. Package authors who would like to include support for fitting models from a @formula are strongly encouraged to directly use schema, apply_schema, and modelcols to handle the table-to-matrix transformations they need."
},

{
    "location": "internals/#",
    "page": "Internals and extending the @formula",
    "title": "Internals and extending the @formula",
    "category": "page",
    "text": "DocTestSetup = quote\n    using StatsModels\n    using Random\n    Random.seed!(1)\nend\nDocTestFilters = [r\"([a-z]*) => \\1\"]"
},

{
    "location": "internals/#Internals-and-extending-the-formula-DSL-1",
    "page": "Internals and extending the @formula",
    "title": "Internals and extending the formula DSL",
    "category": "section",
    "text": "This section is intended to help package developers understand the internals of how a @formula becomes a numerical matrix, in order to use, manipulate, and even extend the DSL.  The Julia @formula is designed to be as extensible as possible through the normal Julian mechanisms of multiple dispatch."
},

{
    "location": "internals/#The-lifecycle-of-a-@formula-1",
    "page": "Internals and extending the @formula",
    "title": "The lifecycle of a @formula",
    "category": "section",
    "text": "A formula goes through a number of stages, starting as an expression that\'s passed to the @formula macro and ending up generating a numeric matrix when ultimately combined with a tabular data source:\"Syntax time\" when only the surface syntax is available, when the @formula macro is invoked.\n\"Schema time\" incorporates information about data invariants (types of each variable, levels of categorical variables, summary statistics for continuous variables) and the overall structure of the data, during the invocation of schema.\n\"Semantics time\" incorporates information about the model type (context), and custom terms, during the call to apply_schema.\n\"Data time\" when the actual data values themselves are available.For in-memory (columnar) tables, there is not much difference between \"data time\" and \"schema time\" in practice, but in principle it\'s important to distinguish between these when dealing with truly streaming data, or large data stores where calculating invariants of the data may be expensive."
},

{
    "location": "internals/#Syntax-time-(@formula)-1",
    "page": "Internals and extending the @formula",
    "title": "Syntax time (@formula)",
    "category": "section",
    "text": "The @formula macro does syntactic transformations of the formula expression. At this point, only the expression itself is available, and there\'s no way to know whether a term corresponds to a continuous or categorical variable.For standard formulae, this amounts to applying the syntactic rules for the DSL operators (expanding * and applying the distributive and associative rules), and wrapping each symbol in a Term constructor:julia> @macroexpand @formula(y ~ 1 + a*b)\n:(Term(:y) ~ ConstantTerm(1) + Term(:a) + Term(:b) + Term(:a) & Term(:b))Note that much of the action happens outside the @formula macro, when the expression returned by the @formula macro is evaluated.  At this point, the Terms are combined to create higher-order terms via overloaded methods for ~, +, and &:julia> using StatsModels;\n\njulia> dump(Term(:a) & Term(:b))\nInteractionTerm{Tuple{Term,Term}}\n  terms: Tuple{Term,Term}\n    1: Term\n      sym: Symbol a\n    2: Term\n      sym: Symbol b\n\njulia> dump(Term(:a) + Term(:b))\nTuple{Term,Term}\n  1: Term\n    sym: Symbol a\n  2: Term\n    sym: Symbol b\n\njulia> dump(Term(:y) ~ Term(:a))\nFormulaTerm{Term,Term}\n  lhs: Term\n    sym: Symbol y\n  rhs: Term\n    sym: Symbol anote: Note\nAs always, you can introspect which method is called withjulia> @which Term(:a) & Term(:b)\n&(terms::AbstractTerm...) in StatsModels at /home/dave/.julia/dev/StatsModels/src/terms.jl:399The reason that the actual construction of higher-order terms is done after the macro is expanded is that it makes it much easier to create a formula programatically:julia> f = Term(:y) ~ sum(term.([1, :a, :b, :c]))\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n  c(unknown)\n\njulia> f == @formula(y ~ 1 + a + b + c)\ntrueThe major exception to this is that non-DSL calls must be specified using the @formula macro.  The reason for this is that non-DSL calls are \"captured\" and turned into anonymous functions that can be evaluated elementwise, which has to happen at compile time.  For instance, the call to log in @formula(y ~ log(a+b)) is converted into the anonymous function (a,b) -> log(a+b).Internally a lot of the work at syntax time is done by the parse! function."
},

{
    "location": "internals/#Schema-time-(schema)-1",
    "page": "Internals and extending the @formula",
    "title": "Schema time (schema)",
    "category": "section",
    "text": "The next phase of life for a formula requires some information about the data it will be used with.  This is represented by a schema, a mapping from placeholder Terms to concrete terms—like ContinuousTerm CategoricalTerm—which represent all the summary information about a data column necessary to create a model matrix from that column.There are a number of ways to construct a schema, ranging from fully automatic to fully manual."
},

{
    "location": "internals/#Fully-automatic:-schema-1",
    "page": "Internals and extending the @formula",
    "title": "Fully automatic: schema",
    "category": "section",
    "text": "The most convenient way to automatically compute a schema is with the schema function.  By default, it will create a schema for every column in the data:julia> using DataFrames    # for pretty printing---any Table will do\n\njulia> df = DataFrame(y = rand(9), a = 1:9, b = rand(9), c = repeat([\"a\",\"b\",\"c\"], 3))\n9×4 DataFrame\n│ Row │ y          │ a     │ b         │ c      │\n│     │ Float64    │ Int64 │ Float64   │ String │\n├─────┼────────────┼───────┼───────────┼────────┤\n│ 1   │ 0.236033   │ 1     │ 0.986666  │ a      │\n│ 2   │ 0.346517   │ 2     │ 0.555751  │ b      │\n│ 3   │ 0.312707   │ 3     │ 0.437108  │ c      │\n│ 4   │ 0.00790928 │ 4     │ 0.424718  │ a      │\n│ 5   │ 0.488613   │ 5     │ 0.773223  │ b      │\n│ 6   │ 0.210968   │ 6     │ 0.28119   │ c      │\n│ 7   │ 0.951916   │ 7     │ 0.209472  │ a      │\n│ 8   │ 0.999905   │ 8     │ 0.251379  │ b      │\n│ 9   │ 0.251662   │ 9     │ 0.0203749 │ c      │\n\njulia> schema(df)\nStatsModels.Schema with 4 entries:\n  y => y\n  a => a\n  b => b\n  c => cHowever, if a term (including a FormulaTerm) is provided, the schema will be computed based only on the necessary variables:julia> schema(@formula(y ~ 1 + a), df)\nStatsModels.Schema with 2 entries:\n  y => y\n  a => a\n\njulia> schema(Term(:a) + Term(:b), df)\nStatsModels.Schema with 2 entries:\n  a => a\n  b => b"
},

{
    "location": "internals/#Fully-manual:-term-constructors-1",
    "page": "Internals and extending the @formula",
    "title": "Fully manual: term constructors",
    "category": "section",
    "text": "While schema is a convenient way to generate a schema automatically from a data source, in some cases it may be preferable to create a schema manually.  In particular, schema peforms a complete sweep through the data, and if your dataset is very large or truly streaming (online), then this may be undesirable.  In such cases, you can construct a schema from instances of the relevant concrete terms (ContinuousTerm or CategoricalTerm), in a number of ways.The constructors for concrete terms provide the maximum level of control.  A ContinuousTerm stores values for the mean, standard deviation, minimum, and maximum, while a CategoricalTerm stores the StatsModels.ContrastsMatrix that defines the mapping from levels to predictors, and these need to be manually supplied to the constructors:warning: Warning\nThe format of the invariants stored in a term are implementation details and subject to change.julia> cont_a = ContinuousTerm(:a, 0., 1., -1., 1.)\na(continuous)\n\njulia> cat_b = CategoricalTerm(:b, StatsModels.ContrastsMatrix(DummyCoding(), [:a, :b, :c]))\nb(DummyCoding:3→2)The Term-concrete term pairs can then be passed to the StatsModels.Schema constructor (a wrapper for the underlying Dict{Term,AbstractTerm}):julia> sch1 = StatsModels.Schema(term(:a) => cont_a, term(:b) => cat_b)\nStatsModels.Schema with 2 entries:\n  a => a\n  b => b"
},

{
    "location": "internals/#Semi-automatic:-data-subsets-1",
    "page": "Internals and extending the @formula",
    "title": "Semi-automatic: data subsets",
    "category": "section",
    "text": "A slightly more convenient method for generating a schema is provided by the concrete_term internal function, which extracts invariants from a data column and returns a concrete type.  This can be used to generate concrete terms from data vectors constructed to have the same invariants that you care about in your actual data (e.g., the same unique values for categorical data, and the same minimum/maximum values or the same mean/variance for continuous):julia> cont_a2 = concrete_term(term(:a), [-1., 1.])\na(continuous)\n\njulia> cat_b2 = concrete_term(term(:b), [:a, :b, :c])\nb(DummyCoding:3→2)\n\njulia> sch2 = StatsModels.Schema(term(:a) => cont_a2, term(:b) => cat_b2)\nStatsModels.Schema with 2 entries:\n  a => a\n  b => bFinally, you could also call schema on a NamedTuple of vectors (e.g., a Tables.ColumnTable) with the necessary invariants:julia> sch3 = schema((a=[-1., 1], b=[:a, :b, :c]))\nStatsModels.Schema with 2 entries:\n  a => a\n  b => b"
},

{
    "location": "internals/#Semantics-time-(apply_schema)-1",
    "page": "Internals and extending the @formula",
    "title": "Semantics time (apply_schema)",
    "category": "section",
    "text": "The next stage of life for a formula happens when semantic information is available, which includes the schema of the data to be transformed as well as the context, or the type of model that will be fit.  This stage is implemented by apply_schema.  Among other things, this instantiates placeholder terms:Terms become ContinuousTerms or CategoricalTerms\nConstantTerms become InterceptTerms\nTuples of terms become MatrixTerms where appropriate to explicitly indicate they should be concatenated into a single model matrix\nAny model-specific (context-specific) interpretation of the terms is made, including transforming calls to functions that have special meaning in particular contexts into their special term types (see the section on Extending @formula syntax below)julia> f = @formula(y ~ 1 + a + b * c)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  a(unknown)\n  b(unknown)\n  c(unknown)\n  b(unknown) & c(unknown)\n\njulia> typeof(f)\nFormulaTerm{Term,Tuple{ConstantTerm{Int64},Term,Term,Term,InteractionTerm{Tuple{Term,Term}}}}\n\njulia> f = apply_schema(f, schema(f, df))\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  1\n  a(continuous)\n  b(continuous)\n  c(DummyCoding:3→2)\n  b(continuous) & c(DummyCoding:3→2)\n\njulia> typeof(f)\nFormulaTerm{ContinuousTerm{Float64},MatrixTerm{Tuple{InterceptTerm{true},ContinuousTerm{Float64},ContinuousTerm{Float64},CategoricalTerm{DummyCoding,String,2},InteractionTerm{Tuple{ContinuousTerm{Float64},CategoricalTerm{DummyCoding,String,2}}}}}}This transformation is done by calling apply_schema(term, schema, modeltype) recursively on each term (the modeltype defaults to StatisticalModel when fitting a statistical model, and Nothing if apply_schema is called with only two arguments).  Because apply_schema dispatches on the term, schema, and model type, this stage allows generic context-aware transformations, based on both the source (schema) and the destination (model type).  This is the primary mechanisms by which the formula DSL can be extended (see below for more details)"
},

{
    "location": "internals/#Data-time-(modelcols)-1",
    "page": "Internals and extending the @formula",
    "title": "Data time (modelcols)",
    "category": "section",
    "text": "At the end of \"schema time\", a formula encapsulates all the information needed to convert a table into a numeric model matrix.  That is, it is ready for \"data time\".  The main API method is modelcols, which when applied to a FormulaTerm returns a tuple of the numeric forms for the left- (response) and right-hand (predictor) sides.julia> resp, pred = modelcols(f, df);\n\njulia> resp\n9-element Array{Float64,1}:\n 0.23603334566204692\n 0.34651701419196046\n 0.3127069683360675\n 0.00790928339056074\n 0.4886128300795012\n 0.21096820215853596\n 0.951916339835734\n 0.9999046588986136\n 0.25166218303197185\n\njulia> pred\n9×7 Array{Float64,2}:\n 1.0  1.0  0.986666   0.0  0.0  0.0       0.0\n 1.0  2.0  0.555751   1.0  0.0  0.555751  0.0\n 1.0  3.0  0.437108   0.0  1.0  0.0       0.437108\n 1.0  4.0  0.424718   0.0  0.0  0.0       0.0\n 1.0  5.0  0.773223   1.0  0.0  0.773223  0.0\n 1.0  6.0  0.28119    0.0  1.0  0.0       0.28119\n 1.0  7.0  0.209472   0.0  0.0  0.0       0.0\n 1.0  8.0  0.251379   1.0  0.0  0.251379  0.0\n 1.0  9.0  0.0203749  0.0  1.0  0.0       0.0203749\nmodelcols can also take a single row from a table, as a NamedTuple:julia> using Tables\n\njulia> modelcols(f, first(Tables.rowtable(df)))\n(0.23603334566204692, [1.0, 1.0, 0.986666, 0.0, 0.0, 0.0, 0.0])\nAny AbstractTerm can be passed to modelcols with a table, which returns one or more numeric arrays:julia> t = f.rhs.terms[end]\nb(continuous) & c(DummyCoding:3→2)\n\njulia> modelcols(t, df)\n9×2 Array{Float64,2}:\n 0.0       0.0\n 0.555751  0.0\n 0.0       0.437108\n 0.0       0.0\n 0.773223  0.0\n 0.0       0.28119\n 0.0       0.0\n 0.251379  0.0\n 0.0       0.0203749\n"
},

{
    "location": "internals/#extending-1",
    "page": "Internals and extending the @formula",
    "title": "Extending @formula syntax",
    "category": "section",
    "text": "Package authors may want to create additional syntax to the @formula DSL so their users can conveniently specify particular kinds of models.  StatsModels.jl provides mechanisms for such extensions that do not rely on compile time \"macro magic\", but on standard julian mechanisms of multiple dispatch.Extensions have three components:Syntax: the Julia function which is given special meaning inside a formula.\nContext: the model type(s) where this extension applies\nBehavior: how tabular data is transformed under this extensionThese correspond to the stages summarized above (syntax time, schema time, and data time)As an example, we\'ll add syntax for specifying a polynomial regression model, which fits a regression using polynomial basis functions of a continuous predictor.The first step is to specify the syntax we\'re going to use.  While it\'s possible to use an existing function, the best practice is to define a new function to make dispatch less ambiguous.using StatsBase\n# syntax: best practice to define a _new_ function\npoly(x, n) = x^n\n\n# type of model where syntax applies: here this applies to any model type\nconst POLY_CONTEXT = Any\n\n# struct for behavior\nstruct PolyTerm <: AbstractTerm\n    term::ContinuousTerm\n    deg::Int\nend\n\nBase.show(io::IO, p::PolyTerm) = print(io, \"poly($(p.term), $(p.deg))\")\n\nfunction StatsModels.apply_schema(t::FunctionTerm{typeof(poly)},\n                                  sch::StatsModels.Schema,\n                                  Mod::Type{<:POLY_CONTEXT})\n    term = apply_schema(t.args_parsed[1], sch, Mod)\n    isa(term, ContinuousTerm) ||\n        throw(ArgumentError(\"PolyTerm only works with continuous terms (got $term)\"))\n    deg = t.args_parsed[2]\n    isa(deg, ConstantTerm) ||\n        throw(ArgumentError(\"PolyTerm degree must be a number (got $deg)\"))\n    PolyTerm(term, deg.n)\nend\n\nfunction StatsModels.modelcols(p::PolyTerm, d::NamedTuple)\n    col = modelcols(p.term, d)\n    reduce(hcat, [col.^n for n in 1:p.deg])\nend\n\nStatsModels.width(p::PolyTerm) = p.deg\n\nStatsBase.coefnames(p::PolyTerm) = coefnames(p.term) .* \"^\" .* string.(1:p.deg)\n\n# output\n\nNow, we can use poly in a formula:julia> data = DataFrame(y = rand(4), a = rand(4), b = [1:4;])\n4×3 DataFrame\n│ Row │ y          │ a        │ b     │\n│     │ Float64    │ Float64  │ Int64 │\n├─────┼────────────┼──────────┼───────┤\n│ 1   │ 0.236033   │ 0.488613 │ 1     │\n│ 2   │ 0.346517   │ 0.210968 │ 2     │\n│ 3   │ 0.312707   │ 0.951916 │ 3     │\n│ 4   │ 0.00790928 │ 0.999905 │ 4     │\n\njulia> f = @formula(y ~ 1 + poly(b, 2) * a)\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  1\n  (b)->poly(b, 2)\n  a(unknown)\n  (b)->poly(b, 2) & a(unknown)\n\njulia> f = apply_schema(f, schema(data))\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  1\n  poly(b, 2)\n  a(continuous)\n  poly(b, 2) & a(continuous)\n\njulia> modelcols(f.rhs, data)\n4×6 Array{Float64,2}:\n 1.0  1.0   1.0  0.488613  0.488613   0.488613\n 1.0  2.0   4.0  0.210968  0.421936   0.843873\n 1.0  3.0   9.0  0.951916  2.85575    8.56725\n 1.0  4.0  16.0  0.999905  3.99962   15.9985\n\njulia> coefnames(f.rhs)\n6-element Array{String,1}:\n \"(Intercept)\"\n \"b^1\"\n \"b^2\"\n \"a\"\n \"b^1 & a\"\n \"b^2 & a\"\nIt\'s also possible to block interpretation of the poly syntax as special in certain contexts by adding additional (more specific) methods.  For instance, we could block PolyTerms being generated for GLM.LinearModel:julia> using GLM\n\njulia> StatsModels.apply_schema(t::FunctionTerm{typeof(poly)},\n                                sch::StatsModels.Schema,\n                                Mod::Type{GLM.LinearModel}) = tNow the poly is interpreted by default as the \"vanilla\" function defined first, which just raises its first argument to the designated power:julia> f = apply_schema(@formula(y ~ 1 + poly(b,2) * a),\n                        schema(data),\n                        GLM.LinearModel)\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  1\n  (b)->poly(b, 2)\n  a(continuous)\n  (b)->poly(b, 2) & a(continuous)\n\njulia> modelcols(f.rhs, data)\n4×4 Array{Float64,2}:\n 1.0   1.0  0.488613   0.488613\n 1.0   4.0  0.210968   0.843873\n 1.0   9.0  0.951916   8.56725\n 1.0  16.0  0.999905  15.9985\n\njulia> coefnames(f.rhs)\n4-element Array{String,1}:\n \"(Intercept)\"\n \"poly(b, 2)\"\n \"a\"\n \"poly(b, 2) & a\"\nBut by using a different context (e.g., the related but more general GLM.GeneralizedLinearModel) we get the custom interpretation:julia> f2 = apply_schema(@formula(y ~ 1 + poly(b,2) * a),\n                         schema(data),\n                         GLM.GeneralizedLinearModel)\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  1\n  poly(b, 2)\n  a(continuous)\n  poly(b, 2) & a(continuous)\n\njulia> modelcols(f2.rhs, data)\n4×6 Array{Float64,2}:\n 1.0  1.0   1.0  0.488613  0.488613   0.488613\n 1.0  2.0   4.0  0.210968  0.421936   0.843873\n 1.0  3.0   9.0  0.951916  2.85575    8.56725\n 1.0  4.0  16.0  0.999905  3.99962   15.9985\n\njulia> coefnames(f2.rhs)\n6-element Array{String,1}:\n \"(Intercept)\"\n \"b^1\"\n \"b^2\"\n \"a\"\n \"b^1 & a\"\n \"b^2 & a\"The definitions of these methods control how models of each type are fit from a formula with a call to poly:julia> sim_dat = DataFrame(b=randn(100));\n\njulia> sim_dat[:y] = randn(100) .+ 1 .+ 2*sim_dat[:b] .+ 3*sim_dat[:b].^2;\n\njulia> fit(LinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat)\nStatsModels.TableRegressionModel{LinearModel{LmResp{Array{Float64,1}},DensePredChol{Float64,LinearAlgebra.Cholesky{Float64,Array{Float64,2}}}},Array{Float64,2}}\n\ny ~ 1 + :(poly(b, 2))\n\nCoefficients:\n────────────────────────────────────────────────────\n             Estimate  Std.Error   t value  Pr(>|t|)\n────────────────────────────────────────────────────\n(Intercept)  0.911363   0.310486   2.93528    0.0042\npoly(b, 2)   2.94442    0.191024  15.4139     <1e-27\n────────────────────────────────────────────────────\n\njulia> fit(GeneralizedLinearModel, @formula(y ~ 1 + poly(b,2)), sim_dat, Normal())\nStatsModels.TableRegressionModel{GeneralizedLinearModel{GlmResp{Array{Float64,1},Normal{Float64},IdentityLink},DensePredChol{Float64,LinearAlgebra.Cholesky{Float64,Array{Float64,2}}}},Array{Float64,2}}\n\ny ~ 1 + poly(b, 2)\n\nCoefficients:\n───────────────────────────────────────────────────\n             Estimate  Std.Error  z value  Pr(>|z|)\n───────────────────────────────────────────────────\n(Intercept)  0.829374  0.131582    6.3031    <1e-9\nb^1          2.13096   0.100552   21.1926    <1e-98\nb^2          3.1132    0.0813107  38.2877    <1e-99\n───────────────────────────────────────────────────\n(a GeneralizeLinearModel with a Normal distribution is equivalent to a LinearModel)"
},

{
    "location": "internals/#Summary-1",
    "page": "Internals and extending the @formula",
    "title": "Summary",
    "category": "section",
    "text": "\"Custom syntax\" means that calls to a particular function in a formula are not interpreted as normal Julia code, but rather as a particular (possibly special) kind of term.Custom syntax is a combination of syntax (Julia function) and term (subtype of AbstractTerm).  This syntax applies in a particular context (schema plus model type, designated via a method of apply_schema), transforming a FunctionTerm{syntax} into another (often custom) term type. This custom term type then specifies special behavior at data time (via a method for modelcols).Finally, note that it\'s easy for a package to intercept the formula terms and manipulate them directly as well, before calling apply_schema or modelcols.  This gives packages great flexibility in how they interpret formula terms."
},

{
    "location": "contrasts/#",
    "page": "Contrast coding categorical variables",
    "title": "Contrast coding categorical variables",
    "category": "page",
    "text": "CurrentModule = StatsModels"
},

{
    "location": "contrasts/#Modeling-categorical-data-1",
    "page": "Contrast coding categorical variables",
    "title": "Modeling categorical data",
    "category": "section",
    "text": "To convert categorical data into a numerical representation suitable for modeling, StatsModels implements a variety of contrast coding systems. Each contrast coding system maps a categorical vector with k levels onto k-1 linearly independent model matrix columns.The following contrast coding systems are implemented:DummyCoding\nEffectsCoding\nHelmertCoding\nContrastsCoding"
},

{
    "location": "contrasts/#StatsModels.setcontrasts!",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.setcontrasts!",
    "category": "function",
    "text": "setcontrasts!(mf::ModelFrame; kwargs...)\nsetcontrasts!(mf::ModelFrame, contrasts::Dict{Symbol})\n\nUpdate the contrasts used for coding categorical variables in ModelFrame in place.  This is accomplished by computing a new schema based on the provided contrasts and the ModelFrame\'s data, and applying it to the ModelFrame\'s FormulaTerm.\n\nNote that only the ModelFrame itself is mutated: because AbstractTerms are immutable, any changes will produce a copy.\n\n\n\n\n\n"
},

{
    "location": "contrasts/#How-to-specify-contrast-coding-1",
    "page": "Contrast coding categorical variables",
    "title": "How to specify contrast coding",
    "category": "section",
    "text": "The default contrast coding system is DummyCoding.  To override this, use the contrasts argument when constructing a ModelFrame:mf = ModelFrame(@formula(y ~ 1 + x), df, contrasts = Dict(:x => EffectsCoding()))To change the contrast coding for one or more variables in place, usesetcontrasts!"
},

{
    "location": "contrasts/#StatsModels.AbstractContrasts",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.AbstractContrasts",
    "category": "type",
    "text": "Interface to describe contrast coding systems for categorical variables.\n\nConcrete subtypes of AbstractContrasts describe a particular way of converting a categorical data vector into numeric columns in a ModelMatrix. Each instantiation optionally includes the levels to generate columns for and the base level. If not specified these will be taken from the data when a ContrastsMatrix is generated (during ModelFrame construction).\n\nConstructors\n\nFor C <: AbstractContrast:\n\nC()                                     # levels are inferred later\nC(levels = ::Vector{Any})               # levels checked against data later\nC(base = ::Any)                         # specify base level\nC(levels = ::Vector{Any}, base = ::Any) # specify levels and base\n\nArguments\n\nlevels: Optionally, the data levels can be specified here.  This allows you to specify the order of the levels.  If specified, the levels will be checked against the levels actually present in the data when the ContrastsMatrix is constructed. Any mismatch will result in an error, because levels missing in the data would lead to empty columns in the model matrix, and levels missing from the contrasts would lead to empty or undefined rows.\nbase: The base level may also be specified.  The actual interpretation of this depends on the particular contrast type, but in general it can be thought of as a \"reference\" level.  It defaults to the first level.\n\nContrast coding systems\n\nDummyCoding - Code each non-base level as a 0-1 indicator column.\nEffectsCoding - Code each non-base level as 1, and base as -1.\nHelmertCoding - Code each non-base level as the difference from the mean of the lower levels\nContrastsCoding - Manually specify contrasts matrix\n\nThe last coding type, ContrastsCoding, provides a way to manually specify a contrasts matrix. For a variable x with k levels, a contrasts matrix M is a k×k-1 matrix, that maps the k levels onto k-1 model matrix columns. Specifically, let X be the full-rank indicator matrix for x, where X[i,j] = 1 if x[i] == levels(x)[j], and 0 otherwise. Then the model matrix columns generated by the contrasts matrix M are Y = X * M.\n\nExtending\n\nThe easiest way to specify custom contrasts is with ContrastsCoding.  But if you want to actually implement a custom contrast coding system, you can subtype AbstractContrasts.  This requires a constructor, a contrasts_matrix method for constructing the actual contrasts matrix that maps from levels to ModelMatrix column values, and (optionally) a termnames method:\n\nmutable struct MyCoding <: AbstractContrasts\n    ...\nend\n\ncontrasts_matrix(C::MyCoding, baseind, n) = ...\ntermnames(C::MyCoding, levels, baseind) = ...\n\n\n\n\n\n"
},

{
    "location": "contrasts/#StatsModels.ContrastsMatrix",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.ContrastsMatrix",
    "category": "type",
    "text": "An instantiation of a contrast coding system for particular levels\n\nThis type is used internally for generating model matrices based on categorical data, and most users will not need to deal with it directly.  Conceptually, a ContrastsMatrix object stands for an instantiation of a contrast coding system for a particular set of categorical data levels.\n\nIf levels are specified in the AbstractContrasts, those will be used, and likewise for the base level (which defaults to the first level).\n\nConstructors\n\nContrastsMatrix(contrasts::AbstractContrasts, levels::AbstractVector)\nContrastsMatrix(contrasts_matrix::ContrastsMatrix, levels::AbstractVector)\n\nArguments\n\ncontrasts::AbstractContrasts: The contrast coding system to use.\nlevels::AbstractVector: The levels to generate contrasts for.\ncontrasts_matrix::ContrastsMatrix: Constructing a ContrastsMatrix from another will check that the levels match.  This is used, for example, in constructing a model matrix from a ModelFrame using different data.\n\n\n\n\n\n"
},

{
    "location": "contrasts/#Interface-1",
    "page": "Contrast coding categorical variables",
    "title": "Interface",
    "category": "section",
    "text": "AbstractContrasts\nContrastsMatrix"
},

{
    "location": "contrasts/#StatsModels.DummyCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.DummyCoding",
    "category": "type",
    "text": "DummyCoding([base[, levels]])\n\nDummy coding generates one indicator column (1 or 0) for each non-base level.\n\nColumns have non-zero mean and are collinear with an intercept column (and lower-order columns for interactions) but are orthogonal to each other. In a regression model, dummy coding leads to an intercept that is the mean of the dependent variable for base level.\n\nAlso known as \"treatment coding\" or \"one-hot encoding\".\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(DummyCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n 0.0  0.0  0.0\n 1.0  0.0  0.0\n 0.0  1.0  0.0\n 0.0  0.0  1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts/#StatsModels.EffectsCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.EffectsCoding",
    "category": "type",
    "text": "EffectsCoding([base[, levels]])\n\nEffects coding generates columns that code each non-base level as the deviation from the base level.  For each non-base level x of variable, a column is generated with 1 where variable .== x and -1 where variable .== base.\n\nEffectsCoding is like DummyCoding, but using -1 for the base level instead of 0.\n\nWhen all levels are equally frequent, effects coding generates model matrix columns that are mean centered (have mean 0).  For more than two levels the generated columns are not orthogonal.  In a regression model with an effects-coded variable, the intercept corresponds to the grand mean.\n\nAlso known as \"sum coding\" or \"simple coding\". Note though that the default in R and SPSS is to use the last level as the base. Here we use the first level as the base, for consistency with other coding systems.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(EffectsCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n -1.0  -1.0  -1.0\n  1.0   0.0   0.0\n  0.0   1.0   0.0\n  0.0   0.0   1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts/#StatsModels.HelmertCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.HelmertCoding",
    "category": "type",
    "text": "HelmertCoding([base[, levels]])\n\nHelmert coding codes each level as the difference from the average of the lower levels.\n\nFor each non-base level, Helmert coding generates a columns with -1 for each of n levels below, n for that level, and 0 above.\n\nWhen all levels are equally frequent, Helmert coding generates columns that are mean-centered (mean 0) and orthogonal.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(HelmertCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n -1.0  -1.0  -1.0\n  1.0  -1.0  -1.0\n  0.0   2.0  -1.0\n  0.0   0.0   3.0\n\n\n\n\n\n"
},

{
    "location": "contrasts/#StatsModels.ContrastsCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.ContrastsCoding",
    "category": "type",
    "text": "ContrastsCoding(mat::Matrix[, base[, levels]])\n\nCoding by manual specification of contrasts matrix. For k levels, the contrasts must be a k by k-1 Matrix.\n\n\n\n\n\n"
},

{
    "location": "contrasts/#Contrast-coding-systems-1",
    "page": "Contrast coding categorical variables",
    "title": "Contrast coding systems",
    "category": "section",
    "text": "DummyCoding\nEffectsCoding\nHelmertCoding\nContrastsCoding"
},

{
    "location": "contrasts/#StatsModels.FullDummyCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.FullDummyCoding",
    "category": "type",
    "text": "FullDummyCoding()\n\nFull-rank dummy coding generates one indicator (1 or 0) column for each level, including the base level. This is sometimes known as  one-hot encoding.\n\nNot exported but included here for the sake of completeness. Needed internally for some situations where a categorical variable with k levels needs to be converted into k model matrix columns instead of the standard k-1.  This occurs when there are missing lower-order terms, as in discussed below in Categorical variables in Formulas.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(StatsModels.FullDummyCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×4 Array{Float64,2}:\n 1.0  0.0  0.0  0.0\n 0.0  1.0  0.0  0.0\n 0.0  0.0  1.0  0.0\n 0.0  0.0  0.0  1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts/#Special-internal-contrasts-1",
    "page": "Contrast coding categorical variables",
    "title": "Special internal contrasts",
    "category": "section",
    "text": "FullDummyCoding"
},

{
    "location": "contrasts/#Further-details-1",
    "page": "Contrast coding categorical variables",
    "title": "Further details",
    "category": "section",
    "text": ""
},

{
    "location": "contrasts/#Categorical-variables-in-Formulas-1",
    "page": "Contrast coding categorical variables",
    "title": "Categorical variables in Formulas",
    "category": "section",
    "text": "Generating model matrices from multiple variables, some of which are categorical, requires special care.  The reason for this is that rank-k-1 contrasts are appropriate for a categorical variable with k levels when it aliases other terms, making it partially redundant.  Using rank-k for such a redundant variable will generally result in a rank-deficient model matrix and a model that can\'t be identified.A categorical variable in a term aliases the term that remains when that variable is dropped.  For example, with categorical a:In a, the sole variable a aliases the intercept term 1.\nIn a&b, the variable a aliases the main effect term b, and vice versa.\nIn a&b&c, the variable a alises the interaction term b&c (regardless of whether b and c are categorical).If a categorical variable aliases another term that is present elsewhere in the formula, we call that variable redundant.  A variable is non-redundant when the term that it alises is not present elsewhere in the formula.  For categorical a, b, and c:In y ~ 1 + a, the a in the main effect of a aliases the intercept 1.\nIn y ~ 0 + a, a does not alias any other terms and is non-redundant.\nIn y ~ 1 + a + a&b:\nThe b in a&b is redundant because it aliases the main effect a: dropping b from a&b leaves a.\nThe a in a&b is non-redundant because it aliases b, which is not present anywhere else in the formula.When constructing a ModelFrame from a Formula, each term is checked for non-redundant categorical variables.  Any such non-redundant variables are \"promoted\" to full rank in that term by using FullDummyCoding instead of the contrasts used elsewhere for that variable.One additional complexity is introduced by promoting non-redundant variables to full rank.  For the purpose of determining redundancy, a full-rank dummy coded categorical variable implicitly introduces the term that it aliases into the formula.  Thus, in y ~ 1 + a + a&b + b&c:In a&b, a aliases the main effect b, which is not explicitly present in the formula.  This makes it non-redundant and so its contrast coding is promoted to FullDummyCoding, which implicitly introduces the main effect of b.\nThen, in b&c, the variable c is now redundant because it aliases the main effect of b, and so it keeps its original contrast coding system."
},

{
    "location": "temporal_terms/#",
    "page": "Temporal variables and Time Series Terms",
    "title": "Temporal variables and Time Series Terms",
    "category": "page",
    "text": ""
},

{
    "location": "temporal_terms/#Temporal-Terms-(Lag/Lead)-1",
    "page": "Temporal variables and Time Series Terms",
    "title": "Temporal Terms (Lag/Lead)",
    "category": "section",
    "text": "When working with time series data it is common to want to access past or future values of your predictors. These are called lagged (past) or lead (future) variables.StatsModels supports basic lead and lag functionality:lag(x, n) accesses data for variable x from n rows (time steps) ago.\nlead(x, n) accesses data for variable x from n rows (time steps) ahead.In both cases, n can be omitted, and it defaults to 1 row. missing is used for any entries that are lagged or lead out of the table.Note that this is a purely structural lead/lag term: it is unaware of any time index of the data. It is up to the user to ensure the data is sorted, and following a regular time interval, which may require inserting additional rows containing missings  to fill in gaps in irregular data.Below is a simple example:julia> using StatsModels, DataFrames\n\njulia> df = DataFrame(y=1:5, x=2:2:10)\n5×2 DataFrame\n│ Row │ y     │ x     │\n│     │ Int64 │ Int64 │\n├─────┼───────┼───────┤\n│ 1   │ 1     │ 2     │\n│ 2   │ 2     │ 4     │\n│ 3   │ 3     │ 6     │\n│ 4   │ 4     │ 8     │\n│ 5   │ 5     │ 10    │\n\njulia> f = @formula(y ~ x + lag(x, 2) + lead(x, 2))\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  x(unknown)\n  (x)->lag(x, 2)\n  (x)->lead(x, 2)\n\njulia> f = apply_schema(f, schema(f, df))\nFormulaTerm\nResponse:\n  y(continuous)\nPredictors:\n  x(continuous)\n  lag(x, 2)\n  lead(x, 2)\n\njulia> modelmatrix(f, df)\n5×3 reshape(::Array{Union{Missing, Float64},2}, 5, 3) with eltype Union{Missing, Float64}:\n  2.0   missing   6.0\n  4.0   missing   8.0\n  6.0  2.0       10.0\n  8.0  4.0         missing\n 10.0  6.0         missing"
},

{
    "location": "api/#",
    "page": "API documentation",
    "title": "API documentation",
    "category": "page",
    "text": "CurrentModule = StatsModels\nDocTestSetup = quote\n    using StatsModels, Random, StatsBase\n    Random.seed!(2001)\nend\nDocTestFilters = [r\"([a-z]*) => \\1\", r\"getfield\\(.*##[0-9]+#[0-9]+\"]"
},

{
    "location": "api/#StatsModels.jl-API-1",
    "page": "API documentation",
    "title": "StatsModels.jl API",
    "category": "section",
    "text": ""
},

{
    "location": "api/#StatsModels.@formula",
    "page": "API documentation",
    "title": "StatsModels.@formula",
    "category": "macro",
    "text": "@formula(ex)\n\nCapture and parse a formula expression as a Formula struct.\n\nA formula is an abstract specification of a dependence between left-hand and right-hand side variables as in, e.g., a regression model.  Each side specifies at a high level how tabular data is to be converted to a numerical matrix suitable for modeling.  This specification looks something like Julia code, is represented as a Julia Expr, but uses special syntax.  The @formula macro takes an expression like y ~ 1 + a*b, transforms it according to the formula syntax rules into a lowered form (like y ~ 1 + a + b + a&b), and constructs a Formula struct which captures the original expression, the lowered expression, and the left- and right-hand-side.\n\nOperators that have special interpretations in this syntax are\n\n~ is the formula separator, where it is a binary operator (the first argument is the left-hand side, and the second is the right-hand side.\n+ concatenates variables as columns when generating a model matrix.\n& representes an interaction between two or more variables, which corresponds to a row-wise kronecker product of the individual terms (or element-wise product if all terms involved are continuous/scalar).\n* expands to all main effects and interactions: a*b is equivalent to a+b+a&b, a*b*c to a+b+c+a&b+a&c+b&c+a&b&c, etc.\n1, 0, and -1 indicate the presence (for 1) or absence (for 0 and -1) of an intercept column.\n\nThe rules that are applied are\n\nThe associative rule (un-nests nested calls to +, &, and *).\nThe distributive rule (interactions & distribute over concatenation +).\nThe * rule expands a*b to a+b+a&b (recursively).\nSubtraction is converted to addition and negation, so x-1 becomes x + -1 (applies only to subtraction of literal 1).\nSingle-argument & calls are stripped, so &(x) becomes the main effect x.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.term",
    "page": "API documentation",
    "title": "StatsModels.term",
    "category": "function",
    "text": "term(x)\n\nWrap argument in an appropriate AbstractTerm type: Symbols become Terms, and Numbers become ConstantTerms.  Any AbstractTerms are unchanged.\n\nExample\n\njulia> ts = term.((1, :a, :b))\n1\na(unknown)\nb(unknown)\n\njulia> typeof(ts)\nTuple{ConstantTerm{Int64},Term,Term}\n\n\n\n\n\n"
},

{
    "location": "api/#StatsBase.coefnames",
    "page": "API documentation",
    "title": "StatsBase.coefnames",
    "category": "function",
    "text": "coefnames(obj::StatisticalModel)\n\nReturn the names of the coefficients.\n\n\n\n\n\ncoefnames(term::AbstractTerm)\n\nReturn the name(s) of column(s) generated by a term.  Return value is either a String or an iterable of Strings.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.modelcols",
    "page": "API documentation",
    "title": "StatsModels.modelcols",
    "category": "function",
    "text": "modelcols(t::AbstractTerm, data)\n\nCreate a numerical \"model columns\" representation of data based on an AbstractTerm.  data can either be a whole table (a property-accessible collection of iterable columns or iterable collection of property-accessible rows, as defined by Tables.jl or a single row (in the form of a NamedTuple of scalar values).  Tables will be converted to a NamedTuple of Vectors (e.g., a Tables.ColumnTable).\n\n\n\n\n\nmodelcols(ts::NTuple{N, AbstractTerm}, data) where N\n\nWhen a tuple of terms is provided, modelcols broadcasts over the individual  terms.  To create a single matrix, wrap the tuple in a MatrixTerm.\n\nExample\n\njulia> d = (a = [1:9;], b = rand(9), c = repeat([\"d\",\"e\",\"f\"], 3));\n\njulia> ts = apply_schema(term.((:a, :b, :c)), schema(d))\na(continuous) \nb(continuous)\nc(DummyCoding:3→2)\n\njulia> cols = modelcols(ts, d)\n([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], [0.718418, 0.488167, 0.708161, 0.774301, 0.584296, 0.324937, 0.989408, 0.333175, 0.65323], [0.0 0.0; 1.0 0.0; … ; 1.0 0.0; 0.0 1.0])\n\njulia> reduce(hcat, cols)\n9×4 Array{Float64,2}:\n 1.0  0.718418  0.0  0.0\n 2.0  0.488167  1.0  0.0\n 3.0  0.708161  0.0  1.0\n 4.0  0.774301  0.0  0.0\n 5.0  0.584296  1.0  0.0\n 6.0  0.324937  0.0  1.0\n 7.0  0.989408  0.0  0.0\n 8.0  0.333175  1.0  0.0\n 9.0  0.65323   0.0  1.0\n\njulia> modelcols(MatrixTerm(ts), d)\n9×4 Array{Float64,2}:\n 1.0  0.718418  0.0  0.0\n 2.0  0.488167  1.0  0.0\n 3.0  0.708161  0.0  1.0\n 4.0  0.774301  0.0  0.0\n 5.0  0.584296  1.0  0.0\n 6.0  0.324937  0.0  1.0\n 7.0  0.989408  0.0  0.0\n 8.0  0.333175  1.0  0.0\n 9.0  0.65323   0.0  1.0\n\n\n\n\n\n"
},

{
    "location": "api/#Formulae-and-terms-1",
    "page": "API documentation",
    "title": "Formulae and terms",
    "category": "section",
    "text": "@formula\nterm\ncoefnames\nmodelcols"
},

{
    "location": "api/#StatsModels.FormulaTerm",
    "page": "API documentation",
    "title": "StatsModels.FormulaTerm",
    "category": "type",
    "text": "FormulaTerm{L,R} <: AbstractTerm\n\nRepresents an entire formula, with a left- and right-hand side.  These can be of any type (captured by the type parameters).  \n\nFields\n\nlhs::L: The left-hand side (e.g., response)\nrhs::R: The right-hand side (e.g., predictors)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.InteractionTerm",
    "page": "API documentation",
    "title": "StatsModels.InteractionTerm",
    "category": "type",
    "text": "InteractionTerm{Ts} <: AbstractTerm\n\nRepresents an interaction between two or more individual terms.  \n\nGenerated by combining multiple AbstractTerms with & (which is what calls to & in a @formula lower to)\n\nFields\n\nterms::Ts: the terms that participate in the interaction.\n\nExample\n\njulia> d = (y = rand(9), a = 1:9, b = rand(9), c = repeat([\"d\",\"e\",\"f\"], 3));\n\njulia> t = InteractionTerm(term.((:a, :b, :c)))\na(unknown) & b(unknown) & c(unknown)\n\njulia> t == term(:a) & term(:b) & term(:c)\ntrue\n\njulia> t = apply_schema(t, schema(d))\na(continuous) & b(continuous) & c(DummyCoding:3→2)\n\njulia> modelcols(t, d)\n9×2 Array{Float64,2}:\n 0.0      0.0    \n 1.09793  0.0    \n 0.0      2.6946 \n 0.0      0.0    \n 4.67649  0.0    \n 0.0      4.47245\n 0.0      0.0    \n 0.64805  0.0    \n 0.0      6.97926\n\njulia> modelcols(t.terms, d)\n([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0], [0.88658, 0.548967, 0.898199, 0.504313, 0.935298, 0.745408, 0.489872, 0.0810062, 0.775473], [0.0 0.0; 1.0 0.0; … ; 1.0 0.0; 0.0 1.0])\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.FunctionTerm",
    "page": "API documentation",
    "title": "StatsModels.FunctionTerm",
    "category": "type",
    "text": "FunctionTerm{Forig,Fanon,Names} <: AbstractTerm\n\nRepresents a call to a Julia function.  The first type parameter is the type of the function as originally specified (e.g., typeof(log)), while the second is the type of the anonymous function that will be applied element-wise to the data table.\n\nThe FunctionTerm also captures the arguments of the original call and parses them as if they were part of a special DSL call, applying the rules to expand *, distribute & over +, and wrap symbols in Terms.  \n\nBy storing the original function as a type parameter and pessimistically parsing the arguments as if they\'re part of a special DSL call, this allows custom syntax to be supported with minimal extra effort.  Packages can dispatch on apply_schema(f::FunctionTerm{typeof(special_syntax)}, schema, ::Type{<:MyModel}) and pull out the arguments parsed as terms from f.args_parsed to construct their own custom terms.\n\nFields\n\nforig::Forig: the original function (e.g., log)\nfanon::Fanon: the generated anonymous function (e.g., (a, b) -> log(1+a+b))\nexorig::Expr: the original expression passed to @formula\nargs_parsed::Vector: the arguments of the call passed to @formula, each  parsed as if the call was a \"special\" DSL call.\n\nType parameters\n\nForig: the type of the original function (e.g., typeof(log))\nFanon: the type of the generated anonymous function\nNames: the names of the arguments to the anonymous function (as a NTuple{N,Symbol})\n\nExample\n\njulia> f = @formula(y ~ log(1 + a + b))\nFormulaTerm\nResponse:\n  y(unknown)\nPredictors:\n  (a,b)->log(1 + a + b)\n\njulia> typeof(f.rhs)\nFunctionTerm{typeof(log),getfield(Main, Symbol(\"##9#10\")),(:a, :b)}\n\njulia> f.rhs.forig(1 + 3 + 4)\n2.0794415416798357\n\njulia> f.rhs.fanon(3, 4)\n2.0794415416798357\n\njulia> modelcols(f.rhs, (a=3, b=4))\n2.0794415416798357\n\njulia> modelcols(f.rhs, (a=[3, 4], b=[4, 5]))\n2-element Array{Float64,1}:\n 2.0794415416798357\n 2.302585092994046 \n\n\n\n\n\n"
},

{
    "location": "api/#Higher-order-terms-1",
    "page": "API documentation",
    "title": "Higher-order terms",
    "category": "section",
    "text": "FormulaTerm\nInteractionTerm\nFunctionTerm"
},

{
    "location": "api/#StatsModels.Term",
    "page": "API documentation",
    "title": "StatsModels.Term",
    "category": "type",
    "text": "Term <: AbstractTerm\n\nA placeholder for a variable in a formula where the type (and necessary data invariants) is not yet known.  This will be converted to a ContinuousTerm or CategoricalTerm by apply_schema.\n\nFields\n\nsym::Symbol: The name of the data column this term refers to.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.ConstantTerm",
    "page": "API documentation",
    "title": "StatsModels.ConstantTerm",
    "category": "type",
    "text": "ConstantTerm{T<:Number} <: AbstractTerm\n\nRepresents a literal number in a formula.  By default will be converted to [InterceptTerm] by apply_schema.\n\nFields\n\nn::T: The number represented by this term.\n\n\n\n\n\n"
},

{
    "location": "api/#Placeholder-terms-1",
    "page": "API documentation",
    "title": "Placeholder terms",
    "category": "section",
    "text": "Term\nConstantTerm"
},

{
    "location": "api/#StatsModels.ContinuousTerm",
    "page": "API documentation",
    "title": "StatsModels.ContinuousTerm",
    "category": "type",
    "text": "ContinuousTerm <: AbstractTerm\n\nRepresents a continuous variable, with a name and summary statistics.\n\nFields\n\nsym::Symbol: The name of the variable\nmean::T: Mean\nvar::T: Variance\nmin::T: Minimum value\nmax::T: Maximum value\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.CategoricalTerm",
    "page": "API documentation",
    "title": "StatsModels.CategoricalTerm",
    "category": "type",
    "text": "CategoricalTerm{C,T,N} <: AbstractTerm\n\nRepresents a categorical term, with a name and ContrastsMatrix\n\nFields\n\nsym::Symbol: The name of the variable\ncontrasts::ContrastsMatrix: A contrasts matrix that captures the unique  values this variable takes on and how they are mapped onto numerical  predictors.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.InterceptTerm",
    "page": "API documentation",
    "title": "StatsModels.InterceptTerm",
    "category": "type",
    "text": "InterceptTerm{HasIntercept} <: AbstractTerm\n\nRepresents the presence or (explicit) absence of an \"intercept\" term in a regression model.  These terms are generated from ConstantTerms in a formula by apply_schema(::ConstantTerm, schema, ::Type{<:StatisticalModel}). A 1 yields InterceptTerm{true}, and 0 or -1 yield InterceptTerm{false} (which explicitly omits an intercept for models which implicitly includes one via the implicit_intercept trait).\n\n\n\n\n\n"
},

{
    "location": "api/#ShiftedArrays.lead",
    "page": "API documentation",
    "title": "ShiftedArrays.lead",
    "category": "function",
    "text": "    lead(term, nsteps::Integer)\n\nThis `@formula` term is used to introduce lead variables.\nFor example `lead(x,1)` effectively adds a new column containing\nthe value of the `x` column from the next row.\nIf there is no such row (e.g. because this is the last row),\nthen the lead column will contain `missing` for that entry.\n\nNote: this is only a basic row-wise lead operation.\nIt is up to the user to ensure that data is sorted by the temporal variable,\nand that observations are spaced with regular time-steps.\n(Which may require adding extra-rows filled with `missing` values.)\n\n\n\n\n\n"
},

{
    "location": "api/#ShiftedArrays.lag",
    "page": "API documentation",
    "title": "ShiftedArrays.lag",
    "category": "function",
    "text": "    lag(term, nsteps::Integer)\n\nThis `@formula` term is used to introduce lagged variables.\nFor example `lag(x,1)` effectively adds a new column containing\nthe value of the `x` column from the previous row.\nIf there is no such row (e.g. because this is the first row),\nthen the lagged column will contain `missing` for that entry.\n\nNote: this is only a basic row-wise lag operation.\nIt is up to the user to ensure that data is sorted by the temporal variable,\nand that observations are spaced with regular time-steps.\n(Which may require adding extra-rows filled with `missing` values.)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.MatrixTerm",
    "page": "API documentation",
    "title": "StatsModels.MatrixTerm",
    "category": "type",
    "text": "MatrixTerm{Ts} <: AbstractTerm\n\nA collection of terms that should be combined to produce a single numeric matrix.\n\nA matrix term is created by apply_schema from a tuple of terms using  collect_matrix_terms, which pulls out all the terms that are matrix terms as determined by the trait function is_matrix_term, which is  true by default for all AbstractTerms.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.collect_matrix_terms",
    "page": "API documentation",
    "title": "StatsModels.collect_matrix_terms",
    "category": "function",
    "text": "collect_matrix_terms(ts::TupleTerm)\ncollect_matrix_terms(t::AbstractTerm) = collect_matrix_term((t, ))\n\nDepending on whether the component terms are matrix terms (meaning they have is_matrix_term(T) == true), collect_matrix_terms will return\n\nA single MatrixTerm (if all components are matrix terms)\nA tuple of the components (if none of them are matrix terms)\nA tuple of terms, with all matrix terms collected into a single MatrixTerm  in the first element of the tuple, and the remaining non-matrix terms passed  through unchanged.\n\nBy default all terms are matrix terms (that is, is_matrix_term(::Type{<:AbstractTerm}) = true), the first case is by far the most common.  The others are provided only for convenience when dealing with specialized terms that can\'t be concatenated into a single model matrix, like random effects terms in MixedModels.jl.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.is_matrix_term",
    "page": "API documentation",
    "title": "StatsModels.is_matrix_term",
    "category": "function",
    "text": "is_matrix_term(::Type{<:AbstractTerm})\n\nDoes this type of term get concatenated with other matrix terms into a single model matrix?  This controls the behavior of the collect_matrix_terms, which collects all of its arguments for which is_matrix_term returns true into a MatrixTerm, and returns the rest unchanged.\n\nSince all \"normal\" terms which describe one or more model matrix columns are matrix terms, this defaults to true for any AbstractTerm.\n\nAn example of a non-matrix term is a random effect term in MixedModels.jl.\n\n\n\n\n\n"
},

{
    "location": "api/#Concrete-terms-1",
    "page": "API documentation",
    "title": "Concrete terms",
    "category": "section",
    "text": "These are all generated by apply_schema.ContinuousTerm\nCategoricalTerm\nInterceptTerm\nlead\nlag\nMatrixTerm\ncollect_matrix_terms\nis_matrix_term"
},

{
    "location": "api/#StatsModels.Schema",
    "page": "API documentation",
    "title": "StatsModels.Schema",
    "category": "type",
    "text": "StatsModels.Schema\n\nStruct that wraps a Dict mapping Terms to their concrete forms.  This exists mainly for dispatch purposes and to support possibly more sophisticated behavior in the future.\n\nA Schema behaves for all intents and purposes like an immutable Dict, and delegates the constructor as well as getindex, get, merge!, merge, keys, and haskey to the wrapped Dict.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.schema",
    "page": "API documentation",
    "title": "StatsModels.schema",
    "category": "function",
    "text": "schema([terms::AbstractVector{<:AbstractTerm}, ]data, hints::Dict{Symbol})\nschema(term::AbstractTerm, data, hints::Dict{Symbol})\n\nCompute all the invariants necessary to fit a model with terms.  A schema is a dict that maps Terms to their concrete instantiations (either CategoricalTerms or ContinuousTerms.  \"Hints\" may optionally be supplied in the form of a Dict mapping term names (as Symbols) to term or contrast types.  If a hint is not provided for a variable,  the appropriate term type will be guessed based on the data type from the data column: any numeric data is assumed to be continuous, and any non-numeric data is assumed to be categorical.\n\nReturns a StatsModels.Schema, which is a wrapper around a Dict mapping Terms to their concrete instantiations (ContinuousTerm or CategoricalTerm).\n\nExample\n\njulia> d = (x=sample([:a, :b, :c], 10), y=rand(10));\n\njulia> ts = [Term(:x), Term(:y)];\n\njulia> schema(ts, d)\nStatsModels.Schema with 2 entries:\n  y => y\n  x => x\n\njulia> schema(ts, d, Dict(:x => HelmertCoding()))\nStatsModels.Schema with 2 entries:\n  y => y\n  x => x\n\njulia> schema(term(:y), d, Dict(:y => CategoricalTerm))\nStatsModels.Schema with 1 entry:\n  y => y\n\nNote that concrete ContinuousTerm and CategoricalTerm and un-typed Terms print the  same in a container, but when printed alone are different:\n\njulia> sch = schema(ts, d)\nStatsModels.Schema with 2 entries:\n  y => y\n  x => x\n\njulia> term(:x)\nx(unknown)\n\njulia> sch[term(:x)]\nx(DummyCoding:3→2)\n\njulia> sch[term(:y)]\ny(continuous)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.concrete_term",
    "page": "API documentation",
    "title": "StatsModels.concrete_term",
    "category": "function",
    "text": "concrete_term(t::Term, data[, hint])\n\nCreate concrete term from the placeholder t based on a data source and optional hint.  If data is a table, the getproperty is used to extract the appropriate column.\n\nThe hint can be a Dict{Symbol} of hints, or a specific hint, a concrete term type (ContinuousTerm or CategoricalTerm), or an instance of some <:AbstractContrasts, in which case a CategoricalTerm will be created using those contrasts.\n\nIf no hint is provided (or hint==nothing), the eltype of the data is used: Numbers are assumed to be continuous, and all others are assumed to be categorical.\n\nExample\n\njulia> concrete_term(term(:a), [1, 2, 3])\na(continuous)\n\njulia> concrete_term(term(:a), [1, 2, 3], nothing)\na(continuous)\n\njulia> concrete_term(term(:a), [1, 2, 3], CategoricalTerm)\na(DummyCoding:3→2)\n\njulia> concrete_term(term(:a), [1, 2, 3], EffectsCoding())\na(EffectsCoding:3→2)\n\njulia> concrete_term(term(:a), [1, 2, 3], Dict(:a=>EffectsCoding()))\na(EffectsCoding:3→2)\n\njulia> concrete_term(term(:a), (a = [1, 2, 3], b = rand(3)))\na(continuous)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.apply_schema",
    "page": "API documentation",
    "title": "StatsModels.apply_schema",
    "category": "function",
    "text": "apply_schema(t, schema::StatsModels.Schema[, Mod::Type = Nothing])\n\nReturn a new term that is the result of applying schema to term t with destination model (type) Mod.  If Mod is omitted, Nothing will be used.\n\nWhen t is a ContinuousTerm or CategoricalTerm already, the term will be returned  unchanged unless a matching term is found in the schema.  This allows  selective re-setting of a schema to change the contrast coding or levels of a  categorical term, or to change a continuous term to categorical or vice versa.\n\nWhen defining behavior for custom term types, it\'s best to dispatch on StatsModels.Schema for the second argument.  Leaving it as ::Any will work in most cases, but cause method ambiguity in some.\n\n\n\n\n\napply_schema(t::AbstractTerm, schema::StatsModels.FullRank, Mod::Type)\n\nApply a schema, under the assumption that when a less-than-full rank model matrix would be produced, categorical terms should be \"promoted\" to full rank (where a categorical variable with k levels would produce k columns, instead of k-1 in the standard contrast coding schemes).  This step is applied automatically when Mod <: StatisticalModel, but other types of models can opt-in by adding a method like\n\nStatsModels.apply_schema(t::FormulaTerm, schema::StatsModels.Schema, Mod::Type{<:MyModelType}) =\n    apply_schema(t, StatsModels.FullRank(schema), mod)\n\nSee the section on Modeling categorical data in the docs for more information on how promotion of categorical variables works.\n\n\n\n\n\n"
},

{
    "location": "api/#Schema-1",
    "page": "API documentation",
    "title": "Schema",
    "category": "section",
    "text": "Schema\nschema\nconcrete_term\napply_schema"
},

{
    "location": "api/#StatsBase.fit",
    "page": "API documentation",
    "title": "StatsBase.fit",
    "category": "function",
    "text": "fit(Mod::Type{<:StatisticalModel}, f::FormulaTerm, data, args...; \n    contrasts::Dict{Symbol}, kwargs...)\n\nConvert tabular data into a numeric response vector and predictor matrix using the formula f, and then fit the specified model type, wrapping the result in a TableRegressionModel or TableStatisticalModel (as appropriate).\n\nThis is intended as a backstop for modeling packages that implement model types that are subtypes of StatsBase.StatisticalModel but do not explicitly support the full StatsModels terms-based interface.  Currently this works by creating a ModelFrame from the formula and data, and then converting this to a ModelMatrix, but this is an internal implementation detail which may change in the near future.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsBase.response",
    "page": "API documentation",
    "title": "StatsBase.response",
    "category": "function",
    "text": "response(obj::RegressionModel)\n\nReturn the model response (a.k.a. the dependent variable).\n\n\n\n\n\n"
},

{
    "location": "api/#StatsBase.modelmatrix",
    "page": "API documentation",
    "title": "StatsBase.modelmatrix",
    "category": "function",
    "text": "modelmatrix(obj::RegressionModel)\n\nReturn the model matrix (a.k.a. the design matrix).\n\n\n\n\n\n"
},

{
    "location": "api/#Modeling-1",
    "page": "API documentation",
    "title": "Modeling",
    "category": "section",
    "text": "fit\nresponse\nmodelmatrix"
},

{
    "location": "api/#StatsModels.implicit_intercept",
    "page": "API documentation",
    "title": "StatsModels.implicit_intercept",
    "category": "function",
    "text": "implicit_intercept(T::Type)\nimplicit_intercept(x::T) = implicit_intercept(T)\n\nReturn true if models of type T should include an implicit intercept even if none is specified in the formula.  Is true by default for all T<:StatisticalModel, and false for others.  To specify that a model type T includes an intercept even if one is not specified explicitly in the formula, overload this function for the corresponding type: implicit_intercept(::Type{<:T}) = true\n\nIf a model has an implicit intercept, it can be explicitly excluded by using 0 in the formula, which generates InterceptTerm{false} with apply_schema.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.drop_intercept",
    "page": "API documentation",
    "title": "StatsModels.drop_intercept",
    "category": "function",
    "text": "drop_intercept(T::Type)\ndrop_intercept(x::T) = drop_intercept(T)\n\nDefine whether a given model automatically drops the intercept. Return false by default.  To specify that a model type T drops the intercept, overload this function for the  corresponding type: drop_intercept(::Type{<:T}) = true\n\nModels that drop the intercept will be fitted without one: the intercept term will be  removed even if explicitly provided by the user. Categorical variables will be expanded  in the rank-reduced form (contrasts for n levels will only produce n-1 columns).\n\n\n\n\n\n"
},

{
    "location": "api/#Traits-1",
    "page": "API documentation",
    "title": "Traits",
    "category": "section",
    "text": "StatsModels.implicit_intercept\nStatsModels.drop_intercept"
},

{
    "location": "api/#StatsModels.ModelFrame",
    "page": "API documentation",
    "title": "StatsModels.ModelFrame",
    "category": "type",
    "text": "ModelFrame(formula, data; model=StatisticalModel, contrasts=Dict())\n\nWrapper that encapsulates a FormulaTerm, schema, data table, and model type.\n\nThis wrapper encapsulates all the information that\'s required to transform data of the same structure as the wrapped data frame into a model matrix (the FormulaTerm), as well as the information about how that formula term was instantiated (the schema and model type)\n\nCreating a model frame involves first extracting the schema for the data (using any contrasts provided as hints), and then applying that schema with apply_schema to the formula in the context of the provided model type.\n\nConstructors\n\nModelFrame(f::FormulaTerm, data; model::Type{M} = StatisticalModel, contrasts::Dict = Dict())\n\nFields\n\nf::FormulaTerm: Formula whose left hand side is the response and right hand side are the predictors.\nschema::Any: The schema that was applied to generate f.\ndata::D: The data table being modeled.  The only restriction is that data  is a table (Tables.istable(data) == true)\nmodel::Type{M}: The type of the model that will be fit from this model frame.\n\nExamples\n\njulia> df = (x = 1:4, y = 5:8)\njulia> mf = ModelFrame(@formula(y ~ 1 + x), df)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.ModelMatrix",
    "page": "API documentation",
    "title": "StatsModels.ModelMatrix",
    "category": "type",
    "text": "ModelMatrix(mf::ModelFrame)\n\nConvert a ModelFrame into a numeric matrix suitable for modeling\n\nFields\n\nm::AbstractMatrix{<:AbstractFloat}: the generated numeric matrix\nassign::Vector{Int} the index of the term corresponding to each column of m.\n\nConstructors\n\nModelMatrix(mf::ModelFrame)\n# Specify the type of the resulting matrix (default Matrix{Float64})\nModelMatrix{T <: AbstractMatrix{<:AbstractFloat}}(mf::ModelFrame)\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.TableStatisticalModel",
    "page": "API documentation",
    "title": "StatsModels.TableStatisticalModel",
    "category": "type",
    "text": "Wrapper for a StatisticalModel that has been fit from a @formula and tabular data.  \n\nMost functions from the StatsBase API are simply delegated to the wrapped model, with the exception of functions like fit, predict, and coefnames where the tabular nature of the data means that additional processing is required or information provided by the formula.\n\nFields\n\nmodel::M the wrapped StatisticalModel.\nmf::ModelFrame encapsulates the formula, schema, and model type.\nmm::ModelMatrix{T} the model matrix that the model was fit from.\n\n\n\n\n\n"
},

{
    "location": "api/#StatsModels.TableRegressionModel",
    "page": "API documentation",
    "title": "StatsModels.TableRegressionModel",
    "category": "type",
    "text": "Wrapper for a RegressionModel that has been fit from a @formula and tabular data.  \n\nMost functions from the StatsBase API are simply delegated to the wrapped model, with the exception of functions like fit, predict, and coefnames where the tabular nature of the data means that additional processing is required or information provided by the formula.\n\nFields\n\nmodel::M the wrapped RegressioModel.\nmf::ModelFrame encapsulates the formula, schema, and model type.\nmm::ModelMatrix{T} the model matrix that the model was fit from.\n\n\n\n\n\n"
},

{
    "location": "api/#Wrappers-1",
    "page": "API documentation",
    "title": "Wrappers",
    "category": "section",
    "text": "warning: Warning\nThese are internal implementation details that are likely to change in the near future.  In particular, the ModelFrame and ModelMatrix wrappers are dispreferred in favor of using terms directly, and can in most cases be replaced by something like# instead of ModelMatrix(ModelFrame(f::FormulaTerm, data, model=MyModel))\nsch = schema(f, data)\nf = apply_schema(f, sch, MyModel)\nresponse, predictors = modelcols(f, data)ModelFrame\nModelMatrix\nStatsModels.TableStatisticalModel\nStatsModels.TableRegressionModel"
},

]}
