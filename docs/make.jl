using Documenter, StatsModels

makedocs()

deploydocs(
    deps = Deps.pip("pygments", "mkdocs", "python-markdown-math"),
    repo = "github.com/JuliaStats/DataFrames.jl.git"
)
