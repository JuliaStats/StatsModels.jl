using Documenter, StatsModels

makedocs(
    sitename = "StatsModels.jl",
    pages = [
        "Introduction" => "index.md",
        "Modeling tabular data" => "formula.md",
        "Internals and extending the `@formula`" => "internals.md",
        "Contrast coding categorical variables" => "contrasts.md",
        "Temporal variables and Time Series Terms" => "temporal_terms.md",
        "API documentation" => "api.md"
    ]
)

deploydocs(
    repo = "github.com/JuliaStats/StatsModels.jl.git"
)
