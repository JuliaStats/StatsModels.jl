using Documenter, StatsModels

DocMeta.setdocmeta!(StatsModels, :DocTestSetup, :(using StatsModels, StatsBase); recursive=true)


using Pkg
Pkg.precompile()

makedocs(
    sitename = "StatsModels.jl",
    pages = [
        "Introduction" => "index.md",
        "Modeling tabular data" => "formula.md",
        "Internals and extending the `@formula`" => "internals.md",
        "Contrast coding categorical variables" => "contrasts.md",
        "Temporal variables and Time Series Terms" => "temporal_terms.md",
        "API documentation" => "api.md"
    ],
    modules = [StatsModels]
)

deploydocs(
    repo = "github.com/JuliaStats/StatsModels.jl.git",
    push_preview = true,
)
