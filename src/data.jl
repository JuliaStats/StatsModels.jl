# Notes:
#
# Add an apply_data step which puts a link to a table on each term, wrapping it
# in a ModelCols struct.  Propogate missing mask up through the terms to allow
# e.g. lead/lag to say that they're going to generate missings

mutable struct ModelCols{T<:TermOrTerms,D}
    term::T
    data::D
end

function apply_data end

apply_data(t::AbstractTerm, data) = ModelCols(t, data)
apply_data(t::InteractionTerm, data) =
    ModelCols(InteractionTerm(apply_data.(t.terms, Ref(data))), data)
apply_data(t::FormulaTerm, data) = ModelCols(FormulaTerm(apply_data(t.lhs, data),
                                                         apply_data(t.rhs, data)),
                                             data)
apply_data(t::MatrixTerm, data) = apply_data.(t.terms, Ref(data))


width(mc::ModelCols) = width(mc.term)

import Base.getindex

getindex(mc::ModelCols{<:CategoricalTerm}, i, j) =
    mc.term.contrasts[mc.data[mc.term.sym, i], j]

