using Documenter, StatsModels

makedocs(
    format = :html,
    sitename = "StatsModels.jl",
    pages = [
        "Introduction" => "index.md",
        "Modeling tabular data" => "formula.md",
        "Internals and extending the `@formula`" => "internals.md",
        "Contrast coding categorical variables" => "contrasts.md",
        "API documentation" => "api.md"
    ]
)

deploydocs(
    julia = "0.6",
    repo = "github.com/JuliaStats/StatsModels.jl.git",
    target = "build",
    deps = nothing,
    make = nothing
)
