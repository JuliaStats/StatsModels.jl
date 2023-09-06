@deprecate(termnames(C::AbstractContrasts, levels::AbstractVector, baseind::Integer),
           coefnames(C::AbstractContrasts, levels::AbstractVector, baseind::Integer),
           false)

function Base.getproperty(cm::ContrastsMatrix, x::Symbol)
    if x === :termnames
        Base.depwarn("the `termnames` field of `ConstrastsMatrix` is deprecated; use `coefnames(cm)` instead.",
                     :ContrastsMatrix)
        return coefnames(cm)
    else
        return getfield(cm, x)
    end
end
