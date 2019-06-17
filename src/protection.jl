abstract type PolyModel end

protect(x) = error("protect should only be used within a @formula")

"""
    ProtectedCtx{OldCtx}
is a context type that is entered during the applictation of a schema to a
`ProtectedTerm`. It holds the `OldCtx`
"""
struct ProtectedCtx{OldCtx} end
function StatsModels.apply_schema(t::CallTerm{typeof(protect)}, sch, Mod::Type)
    length(t.args_parsed) == 1 || throw(ArgumentError("`protect` only applies to a single term."))
    parsed_term = t.args_parsed[1]
    return apply_schema(parsed_term, sch, ProtectedCtx{Mod})
end


unprotect(x) = error("unprotect should only be used within a @formula")
function StatsModels.apply_schema(t::CallTerm{typeof(unprotect)}, sch, Mod::Type)
    throw(DomainError("`unprotect` used outside a protected context."))
end
function StatsModels.apply_schema(t::CallTerm{typeof(unprotect)}, sch, Mod::Type{<:ProtectedCtx{OldCtx}}) where OldCtx
    length(t.args_parsed) == 1 || throw(ArgumentError("`unprotect` only applies to a single term."))
    parsed_term = t.args_parsed[1]
    return apply_schema(parsed_term, sch, OldCtx)
end

## Defintion of how things act while protected:

# TODO: Transform & and + and * into FunctionTerms

apply_schema(t::ConstantTerm, schema, Mod::Type{<:ProtectedCtx}) = t.n
apply_schema(ct::CallTerm, schema, Mod::Type{<:ProtectedCtx})  = call_fallback_apply_schema(ct, schema, Mod)
