using Documenter, StatsModels, StatsAPI

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
    modules = [StatsModels, StatsAPI],
    doctestfilters = [r"([a-z]*) => \1", r"getfield\(.*##[0-9]+#[0-9]+"],
    strict=Documenter.except(:missing_docs)
)

deploydocs(
    repo = "github.com/JuliaStats/StatsModels.jl.git",
    push_preview = true,
)
