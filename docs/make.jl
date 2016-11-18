using Documenter, StatsModels

makedocs()

deploydocs(
    deps = Deps.pip("pygments", "mkdocs", "python-markdown-math", "mkdocs-material"),
    repo = "github.com/JuliaStats/StatsModels.jl.git"
)
