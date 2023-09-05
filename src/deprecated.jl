@deprecate(termnames(C::AbstractContrasts, levels::AbstractVector, baseind::Integer),
           coefnames(C::AbstractContrasts, levels::AbstractVector, baseind::Integer),
           false)

function Base.getproperty(cm::ContrastsMatrix, x::Symbol)
    if x === :termnames 
        Base.depwarn("The `termnames` field has been renamed `coefnames`.", :ContrastsMatrix)
        x = :coefnames
    end

    return getfield(cm, x)
end
