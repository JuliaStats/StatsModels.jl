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


# Outside of a @formula unprotect strips the protect wrapper
unprotect(t::CallTerm{typeof(protect)}) = t.args_parsed[1]
unprotect(t) = t
function StatsModels.apply_schema(t::CallTerm{typeof(unprotect)}, sch, Mod::Type)
    throw(DomainError("`unprotect` used outside a protected context."))
end
function StatsModels.apply_schema(t::CallTerm{typeof(unprotect)}, sch, Mod::Type{<:ProtectedCtx{OldCtx}}) where OldCtx
    length(t.args_parsed) == 1 || throw(ArgumentError("`unprotect` only applies to a single term."))
    parsed_term = t.args_parsed[1]
    return apply_schema(parsed_term, sch, OldCtx)
end

## Defintion of how things act while protected:

# TODO: Transform * into FunctionTerms
# https://github.com/JuliaStats/StatsModels.jl/issues/119

apply_schema(t::ConstantTerm, schema, Mod::Type{<:ProtectedCtx}) = t

function direct_call(op, arg_terms::Tuple)
    names = Tuple(termvars(arg_terms))
    ex = Expr(:call, nameof(op), names...)
    ct = CallTerm{typeof(op), names}(+, ex, t)
    return call_fallback_apply_schema(ct, schema, Mod)
end
function apply_schema(t::TupleTerm, schema, Mod::Type{<:ProtectedCtx})
    # TupleTerm is what is created by `x+y`, we need to turn that back into addition.
    return direct_call(+, t)
end

function apply_schema(t::InteractionTerm, schema, Mod::Type{<:ProtectedCtx})
    # InteractionTerm is what is created by `x&y`, we need to turn that back into bitwise and.
    return direct_call(&, t.terms)
end


# Lets not do the below by default. Instead overloaded call terms should opt into the fallback for during ProtectedCtx
# that way we avoid and ambiguity error.
# apply_schema(ct::CallTerm, schema, Mod::Type{<:ProtectedCtx})  = call_fallback_apply_schema(ct, schema, Mod)
