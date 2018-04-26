function Formula(lhs, rhs)
    Base.depwarn("Formula(lhs, rhs) is deprecated. Use @eval(@formula(\$lhs ~ \$rhs)) if " *
                 "parsing is required, or Formula(ex_orig, ex, lhs, rhs) if not",
                 :Formula)
    Formula(:(), :($lhs ~ $rhs), lhs, rhs)
end
