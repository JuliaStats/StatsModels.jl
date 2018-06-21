var documenterSearchIndex = {"docs": [

{
    "location": "index.html#",
    "page": "Introduction",
    "title": "Introduction",
    "category": "page",
    "text": ""
},

{
    "location": "index.html#StatsModels-Documentation-1",
    "page": "Introduction",
    "title": "StatsModels Documentation",
    "category": "section",
    "text": "This package provides common abstractions and utilities for specifying, fitting, and evaluating statistical models.  The goal is to provide an API for package developers implementing different kinds of statistical models (see the GLM package for example), and utilities that are generally useful for both users and developers when dealing with statistical models and tabular data.Formula notation for specifying models based on tabular data\nFormula\nModelFrame\nModelMatrix\nContrast coding for categorical data\nAbstract model types\nStatisticalModel\nRegressionModelMuch of this package was formerly part of DataFrames and StatsBase."
},

{
    "location": "formula.html#",
    "page": "Modeling tabular data",
    "title": "Modeling tabular data",
    "category": "page",
    "text": "CurrentModule = StatsModels\nDocTestSetup = quote\n    using StatsModels\nend"
},

{
    "location": "formula.html#Modeling-tabular-data-1",
    "page": "Modeling tabular data",
    "title": "Modeling tabular data",
    "category": "section",
    "text": "Most statistical models require that data be represented as a Matrix-like collection of a single numeric type.  Much of the data we want to model, however, is tabular data, where data is represented as a collection of fields with possibly heterogeneous types.  One of the primary goals of StatsModels is to make it simpler to transform tabular data into matrix format suitable for statistical modeling.At the moment, \"tabular data\" means an AbstractDataFrame.  Ultimately, the goal is to support any tabular data format that adheres to a minimal API, regardless of backend."
},

{
    "location": "formula.html#The-Formula-type-1",
    "page": "Modeling tabular data",
    "title": "The Formula type",
    "category": "section",
    "text": "The basic conceptual tool for this is the Formula, which has a left side and a right side, separated by ~. Formulas are constructed using the @formula macro:julia> @formula(y ~ 1 + a)\nFormula: y ~ 1 + aNote that the @formula macro must be called with parentheses to ensure that the formula is parsed properly.The left side of a formula conventionally represents dependent variables, and the right side independent variables (or regressors).  Terms are separated by +.  Basic terms are the integers 1 or 0—evaluated as the presence or absence of a constant intercept term, respectively—and variables like x, which will evaluate to the data source column with that name as a symbol (:x).Individual variables can be combined into interaction terms with &, as in a&b, which will evaluate to the product of the columns named :a and :b. If either a or b are categorical, then the interaction term a&b generates all the product of each pair of the columns of a and b.It\'s often convenient to include main effects and interactions for a number of variables.  The * operator does this, expanding in the following way:julia> Formula(StatsModels.Terms(@formula(y ~ 1 + a*b)))\nFormula: y ~ 1 + a + b + a & b(We trigger parsing of the formula using the internal Terms type to show how the Formula expands).This applies to higher-order interactions, too: a*b*c expands to the main effects, all two-way interactions, and the three way interaction a&b&c:julia> Formula(StatsModels.Terms(@formula(y ~ 1 + a*b*c)))\nFormula: y ~ 1 + a + b + c + a & b + a & c + b & c + &(a, b, c)Both the * and the & operators act like multiplication, and are distributive over addition:julia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) & c)))\nFormula: y ~ 1 + a & c + b & c\n\njulia> Formula(StatsModels.Terms(@formula(y ~ 1 + (a+b) * c)))\nFormula: y ~ 1 + a + b + c + a & c + b & c"
},

{
    "location": "formula.html#Constructing-a-formula-programmatically-1",
    "page": "Modeling tabular data",
    "title": "Constructing a formula programmatically",
    "category": "section",
    "text": "Because a Formula is created at compile time with the @formula macro, creating one programmatically means dipping into Julia\'s metaprogramming facilities.Let\'s say you have a variable lhs:julia> lhs = :y\n:yand you want to create a formula whose left-hand side is the value of lhs, as injulia> @formula(y ~ 1 + x)\nFormula: y ~ 1 + xSimply using the Julia interpolation syntax @formula($lhs ~ 1 + x) won\'t work, because @formula runs at compile time, before anything about the value of lhs is known.  Instead, you need to construct and evaluate the correct call to @formula.  The most concise way to do this is with @eval:julia> @eval @formula($lhs ~ 1 + x)\nFormula: y ~ 1 + xThe @eval macro does two very different things in a single, convenient step:Generate a quoted expression using $-interpolation to insert the run-time value of lhs into the call to the @formula macro.\nEvaluate this expression using eval.An equivalent but slightly more verbose way of doing the same thing is:julia> formula_ex = :(@formula($lhs ~ 1 + x))\n:(@formula y ~ 1 + x)\n\njulia> eval(formula_ex)\nFormula: y ~ 1 + x"
},

{
    "location": "formula.html#StatsModels.Formula",
    "page": "Modeling tabular data",
    "title": "StatsModels.Formula",
    "category": "type",
    "text": "Formula(t::Terms)\n\nReconstruct a Formula from Terms.\n\n\n\n\n\n"
},

{
    "location": "formula.html#StatsModels.dropterm",
    "page": "Modeling tabular data",
    "title": "StatsModels.dropterm",
    "category": "function",
    "text": "dropterm(f::Formula, trm::Symbol)\n\nReturn a copy of f without the term trm.\n\nExamples\n\njulia> dropterm(@formula(foo ~ 1 + bar + baz), :bar)\nFormula: foo ~ 1 + baz\n\njulia> dropterm(@formula(foo ~ 1 + bar + baz), 1)\nFormula: foo ~ 0 + bar + baz\n\n\n\n\n\n"
},

{
    "location": "formula.html#Technical-details-1",
    "page": "Modeling tabular data",
    "title": "Technical details",
    "category": "section",
    "text": "You may be wondering why formulas in Julia require a macro, while in R they appear \"bare.\"  R supports nonstandard evaluation, allowing the formula to remain an unevaluated object while its terms are parsed out. Julia uses a much more standard evaluation mechanism, making this impossible using normal expressions. However, unlike R, Julia provides macros to explicitly indicate when code itself will be manipulated before it\'s evaluated. By constructing a formula using a macro, we\'re able to provide convenient, R-like syntax and semantics.The formula syntactic transformations are applied at parse time when using the @formula macro.  You can see this with using @macroexpand:@macroexpand @formula y ~ 1 + (a+b)*c\n:((StatsModels.Formula)($(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + (a + b) * c)))))), $(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + a + b + c + a & c + b & c)))))), :y, $(Expr(:copyast, :($(QuoteNode(:(1 + a + b + c + a & c + b & c))))))))Or more legibly:((StatsModels.Formula)($(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + (a + b) * c)))))),\n                        $(Expr(:copyast, :($(QuoteNode(:(y ~ 1 + a + b + c + a & c + b & c)))))),\n                        :y,\n                        $(Expr(:copyast, :($(QuoteNode(:(1 + a + b + c + a & c + b & c))))))))The @formula macro re-writes the formula expression y ~ 1 + (a+b)*c as a call to the Formula constructor.  The arguments of the constructor correspond to the fields of the Formula struct, which are, in order:ex_orig: the original expression :(y ~ 1+(a+b)*c)\nex: the parsed expression :(y ~ 1+a+b+a&c+b&c)\nlhs: the left-hand side :y\nrhs: the right-hand side :(1+a+b+a&c+b&c)Formula\ndropterm"
},

{
    "location": "formula.html#StatsModels.ModelFrame",
    "page": "Modeling tabular data",
    "title": "StatsModels.ModelFrame",
    "category": "type",
    "text": "Wrapper which combines Formula (Terms) and an AbstractDataFrame\n\nThis wrapper encapsulates all the information that\'s required to transform data of the same structure as the wrapped data frame into a model matrix.  This goes above and beyond what\'s expressed in the Formula itself, for instance including information on how each categorical variable should be coded.\n\nCreating a ModelFrame first parses the Formula into Terms, checks which variables are categorical and determines the appropriate contrasts to use, and then creates the necessary contrasts matrices and stores the results.\n\nConstructors\n\nModelFrame(f::Formula, df::AbstractDataFrame; contrasts::Dict = Dict())\nModelFrame(ex::Expr, d::AbstractDataFrame; contrasts::Dict = Dict())\nModelFrame(terms::Terms, df::AbstractDataFrame; contrasts::Dict = Dict())\n# Inner constructors:\nModelFrame(df::AbstractDataFrame, terms::Terms, missing::BitArray)\nModelFrame(df::AbstractDataFrame, terms::Terms, missing::BitArray, contrasts::Dict{Symbol, ContrastsMatrix})\n\nArguments\n\nf::Formula: Formula whose left hand side is the response and right hand side are the predictors.\ndf::AbstractDataFrame: The data being modeled.  This is used at this stage to determine which variables are categorical, and otherwise held for ModelMatrix.\ncontrasts::Dict: An optional Dict of contrast codings for each categorical variable.  Any unspecified variables will have DummyCoding.  As a keyword argument, these can be either instances of a subtype of AbstractContrasts, or a ContrastsMatrix.  For the inner constructor, they must be ContrastsMatrixes.\nex::Expr: An expression which will be converted into a Formula.\nterms::Terms: For inner constructor, the parsed Terms from the Formula.\nmissing::BitArray: For inner constructor, indicates whether each row of df contains any missing data.\n\nExamples\n\njulia> df = DataFrame(x = 1:4, y = 5:9)\njulia> mf = ModelFrame(y ~ 1 + x, df)\n\n\n\n\n\n"
},

{
    "location": "formula.html#StatsModels.ModelMatrix",
    "page": "Modeling tabular data",
    "title": "StatsModels.ModelMatrix",
    "category": "type",
    "text": "Convert a ModelFrame into a numeric matrix suitable for modeling\n\nConstructors\n\nModelMatrix(mf::ModelFrame)\n# Specify the type of the resulting matrix (default Matrix{Float64})\nModelMatrix{T <: AbstractFloatMatrix}(mf::ModelFrame)\n\n\n\n\n\n"
},

{
    "location": "formula.html#StatsModels.Terms",
    "page": "Modeling tabular data",
    "title": "StatsModels.Terms",
    "category": "type",
    "text": "Representation of parsed Formula\n\nThis is an internal type whose implementation is likely to change in the near future.\n\n\n\n\n\n"
},

{
    "location": "formula.html#The-ModelFrame-and-ModelMatrix-types-1",
    "page": "Modeling tabular data",
    "title": "The ModelFrame and ModelMatrix types",
    "category": "section",
    "text": "The main use of Formulas is for fitting statistical models based on tabular data.  From the user\'s perspective, this is done by fit methods that take a Formula and a DataFrame instead of numeric matrices.Internally, this is accomplished in three stages:The Formula is parsed into Terms.\nThe Terms and the data source are wrapped in a ModelFrame.\nA numeric ModelMatrix is generated from the ModelFrame and passed to the model\'s fit method.ModelFrame\nModelMatrix\nTerms"
},

{
    "location": "contrasts.html#",
    "page": "Contrast coding categorical variables",
    "title": "Contrast coding categorical variables",
    "category": "page",
    "text": "CurrentModule = StatsModels"
},

{
    "location": "contrasts.html#Modeling-categorical-data-1",
    "page": "Contrast coding categorical variables",
    "title": "Modeling categorical data",
    "category": "section",
    "text": "To convert categorical data into a numerical representation suitable for modeling, StatsModels implements a variety of contrast coding systems. Each contrast coding system maps a categorical vector with k levels onto k-1 linearly independent model matrix columns.The following contrast coding systems are implemented:DummyCoding\nEffectsCoding\nHelmertCoding\nContrastsCoding"
},

{
    "location": "contrasts.html#StatsModels.setcontrasts!",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.setcontrasts!",
    "category": "function",
    "text": "setcontrasts!(mf::ModelFrame, new_contrasts::Dict)\n\nModify the contrast coding system of a ModelFrame in place.\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#How-to-specify-contrast-coding-1",
    "page": "Contrast coding categorical variables",
    "title": "How to specify contrast coding",
    "category": "section",
    "text": "The default contrast coding system is DummyCoding.  To override this, use the contrasts argument when constructing a ModelFrame:mf = ModelFrame(@formula(y ~ 1 + x), df, contrasts = Dict(:x => EffectsCoding()))To change the contrast coding for one or more variables in place, usesetcontrasts!"
},

{
    "location": "contrasts.html#StatsModels.AbstractContrasts",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.AbstractContrasts",
    "category": "type",
    "text": "Interface to describe contrast coding systems for categorical variables.\n\nConcrete subtypes of AbstractContrasts describe a particular way of converting a categorical data vector into numeric columns in a ModelMatrix. Each instantiation optionally includes the levels to generate columns for and the base level. If not specified these will be taken from the data when a ContrastsMatrix is generated (during ModelFrame construction).\n\nConstructors\n\nFor C <: AbstractContrast:\n\nC()                                     # levels are inferred later\nC(levels = ::Vector{Any})               # levels checked against data later\nC(base = ::Any)                         # specify base level\nC(levels = ::Vector{Any}, base = ::Any) # specify levels and base\n\nArguments\n\nlevels: Optionally, the data levels can be specified here.  This allows you to specify the order of the levels.  If specified, the levels will be checked against the levels actually present in the data when the ContrastsMatrix is constructed. Any mismatch will result in an error, because levels missing in the data would lead to empty columns in the model matrix, and levels missing from the contrasts would lead to empty or undefined rows.\nbase: The base level may also be specified.  The actual interpretation of this depends on the particular contrast type, but in general it can be thought of as a \"reference\" level.  It defaults to the first level.\n\nContrast coding systems\n\nDummyCoding - Code each non-base level as a 0-1 indicator column.\nEffectsCoding - Code each non-base level as 1, and base as -1.\nHelmertCoding - Code each non-base level as the difference from the mean of the lower levels\nContrastsCoding - Manually specify contrasts matrix\n\nThe last coding type, ContrastsCoding, provides a way to manually specify a contrasts matrix. For a variable x with k levels, a contrasts matrix M is a k×k-1 matrix, that maps the k levels onto k-1 model matrix columns. Specifically, let X be the full-rank indicator matrix for x, where X[i,j] = 1 if x[i] == levels(x)[j], and 0 otherwise. Then the model matrix columns generated by the contrasts matrix M are Y = X * M.\n\nExtending\n\nThe easiest way to specify custom contrasts is with ContrastsCoding.  But if you want to actually implement a custom contrast coding system, you can subtype AbstractContrasts.  This requires a constructor, a contrasts_matrix method for constructing the actual contrasts matrix that maps from levels to ModelMatrix column values, and (optionally) a termnames method:\n\nmutable struct MyCoding <: AbstractContrasts\n    ...\nend\n\ncontrasts_matrix(C::MyCoding, baseind, n) = ...\ntermnames(C::MyCoding, levels, baseind) = ...\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#StatsModels.ContrastsMatrix",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.ContrastsMatrix",
    "category": "type",
    "text": "An instantiation of a contrast coding system for particular levels\n\nThis type is used internally for generating model matrices based on categorical data, and most users will not need to deal with it directly.  Conceptually, a ContrastsMatrix object stands for an instantiation of a contrast coding system for a particular set of categorical data levels.\n\nIf levels are specified in the AbstractContrasts, those will be used, and likewise for the base level (which defaults to the first level).\n\nConstructors\n\nContrastsMatrix(contrasts::AbstractContrasts, levels::AbstractVector)\nContrastsMatrix(contrasts_matrix::ContrastsMatrix, levels::AbstractVector)\n\nArguments\n\ncontrasts::AbstractContrasts: The contrast coding system to use.\nlevels::AbstractVector: The levels to generate contrasts for.\ncontrasts_matrix::ContrastsMatrix: Constructing a ContrastsMatrix from another will check that the levels match.  This is used, for example, in constructing a model matrix from a ModelFrame using different data.\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#Interface-1",
    "page": "Contrast coding categorical variables",
    "title": "Interface",
    "category": "section",
    "text": "AbstractContrasts\nContrastsMatrix"
},

{
    "location": "contrasts.html#StatsModels.DummyCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.DummyCoding",
    "category": "type",
    "text": "DummyCoding([base[, levels]])\n\nDummy coding generates one indicator column (1 or 0) for each non-base level.\n\nColumns have non-zero mean and are collinear with an intercept column (and lower-order columns for interactions) but are orthogonal to each other. In a regression model, dummy coding leads to an intercept that is the mean of the dependent variable for base level.\n\nAlso known as \"treatment coding\" or \"one-hot encoding\".\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(DummyCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n 0.0  0.0  0.0\n 1.0  0.0  0.0\n 0.0  1.0  0.0\n 0.0  0.0  1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#StatsModels.EffectsCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.EffectsCoding",
    "category": "type",
    "text": "EffectsCoding([base[, levels]])\n\nEffects coding generates columns that code each non-base level as the deviation from the base level.  For each non-base level x of variable, a column is generated with 1 where variable .== x and -1 where variable .== base.\n\nEffectsCoding is like DummyCoding, but using -1 for the base level instead of 0.\n\nWhen all levels are equally frequent, effects coding generates model matrix columns that are mean centered (have mean 0).  For more than two levels the generated columns are not orthogonal.  In a regression model with an effects-coded variable, the intercept corresponds to the grand mean.\n\nAlso known as \"sum coding\" or \"simple coding\". Note though that the default in R and SPSS is to use the last level as the base. Here we use the first level as the base, for consistency with other coding systems.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(EffectsCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n -1.0  -1.0  -1.0\n  1.0   0.0   0.0\n  0.0   1.0   0.0\n  0.0   0.0   1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#StatsModels.HelmertCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.HelmertCoding",
    "category": "type",
    "text": "HelmertCoding([base[, levels]])\n\nHelmert coding codes each level as the difference from the average of the lower levels.\n\nFor each non-base level, Helmert coding generates a columns with -1 for each of n levels below, n for that level, and 0 above.\n\nWhen all levels are equally frequent, Helmert coding generates columns that are mean-centered (mean 0) and orthogonal.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(HelmertCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×3 Array{Float64,2}:\n -1.0  -1.0  -1.0\n  1.0  -1.0  -1.0\n  0.0   2.0  -1.0\n  0.0   0.0   3.0\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#StatsModels.ContrastsCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.ContrastsCoding",
    "category": "type",
    "text": "ContrastsCoding(mat::Matrix[, base[, levels]])\n\nCoding by manual specification of contrasts matrix. For k levels, the contrasts must be a k by k-1 Matrix.\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#Contrast-coding-systems-1",
    "page": "Contrast coding categorical variables",
    "title": "Contrast coding systems",
    "category": "section",
    "text": "DummyCoding\nEffectsCoding\nHelmertCoding\nContrastsCoding"
},

{
    "location": "contrasts.html#StatsModels.FullDummyCoding",
    "page": "Contrast coding categorical variables",
    "title": "StatsModels.FullDummyCoding",
    "category": "type",
    "text": "FullDummyCoding()\n\nFull-rank dummy coding generates one indicator (1 or 0) column for each level, including the base level.\n\nNot exported but included here for the sake of completeness. Needed internally for some situations where a categorical variable with k levels needs to be converted into k model matrix columns instead of the standard k-1.  This occurs when there are missing lower-order terms, as in discussed below in Categorical variables in Formulas.\n\nExamples\n\njulia> StatsModels.ContrastsMatrix(StatsModels.FullDummyCoding(), [\"a\", \"b\", \"c\", \"d\"]).matrix\n4×4 Array{Float64,2}:\n 1.0  0.0  0.0  0.0\n 0.0  1.0  0.0  0.0\n 0.0  0.0  1.0  0.0\n 0.0  0.0  0.0  1.0\n\n\n\n\n\n"
},

{
    "location": "contrasts.html#Special-internal-contrasts-1",
    "page": "Contrast coding categorical variables",
    "title": "Special internal contrasts",
    "category": "section",
    "text": "FullDummyCoding"
},

{
    "location": "contrasts.html#Further-details-1",
    "page": "Contrast coding categorical variables",
    "title": "Further details",
    "category": "section",
    "text": ""
},

{
    "location": "contrasts.html#Categorical-variables-in-Formulas-1",
    "page": "Contrast coding categorical variables",
    "title": "Categorical variables in Formulas",
    "category": "section",
    "text": "Generating model matrices from multiple variables, some of which are categorical, requires special care.  The reason for this is that rank-k-1 contrasts are appropriate for a categorical variable with k levels when it aliases other terms, making it partially redundant.  Using rank-k for such a redundant variable will generally result in a rank-deficient model matrix and a model that can\'t be identified.A categorical variable in a term aliases the term that remains when that variable is dropped.  For example, with categorical a:In a, the sole variable a aliases the intercept term 1.\nIn a&b, the variable a aliases the main effect term b, and vice versa.\nIn a&b&c, the variable a alises the interaction term b&c (regardless of whether b and c are categorical).If a categorical variable aliases another term that is present elsewhere in the formula, we call that variable redundant.  A variable is non-redundant when the term that it alises is not present elsewhere in the formula.  For categorical a, b, and c:In y ~ 1 + a, the a in the main effect of a aliases the intercept 1.\nIn y ~ 0 + a, a does not alias any other terms and is non-redundant.\nIn y ~ 1 + a + a&b:\nThe b in a&b is redundant because it aliases the main effect a: dropping b from a&b leaves a.\nThe a in a&b is non-redundant because it aliases b, which is not present anywhere else in the formula.When constructing a ModelFrame from a Formula, each term is checked for non-redundant categorical variables.  Any such non-redundant variables are \"promoted\" to full rank in that term by using FullDummyCoding instead of the contrasts used elsewhere for that variable.One additional complexity is introduced by promoting non-redundant variables to full rank.  For the purpose of determining redundancy, a full-rank dummy coded categorical variable implicitly introduces the term that it aliases into the formula.  Thus, in y ~ 1 + a + a&b + b&c:In a&b, a aliases the main effect b, which is not explicitly present in the formula.  This makes it non-redundant and so its contrast coding is promoted to FullDummyCoding, which implicitly introduces the main effect of b.\nThen, in b&c, the variable c is now redundant because it aliases the main effect of b, and so it keeps its original contrast coding system."
},

]}
