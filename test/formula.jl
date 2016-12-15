module TestFormula

using Base.Test
using StatsModels
using Compat

# TODO:
# - grouped variables in formulas with interactions
# - is it fast?  Can expand() handle DataFrames?
# - deal with intercepts
# - implement ^2 for datavector's
# - support more transformations with I()?

## Formula parsing
import StatsModels: @model, Formula, Terms

## totally empty
t = Terms(Formula(nothing, 0))
@test t.response == false
@test t.intercept == false
@test t.terms == []
@test t.eterms == []

## empty RHS
t = Terms(@model y => 0)
@test t.intercept == false
@test t.terms == []
@test t.eterms == [:y]
t = Terms(@model y => -1)
@test t.intercept == false
@test t.terms == []

## intercept-only
t = Terms(@model y => 1)
@test t.response == true
@test t.intercept == true
@test t.terms == []
@test t.eterms == [:y]

## terms add
t = Terms(@model y => 1 + x1 + x2)
@test t.intercept == true
@test t.terms == [:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## implicit intercept behavior:
t = Terms(@model y => x1 + x2)
@test t.intercept == true
@test t.terms == [:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## no intercept
t = Terms(@model y => 0 + x1 + x2)
@test t.intercept == false
@test t.terms == [:x1, :x2]

@test t == Terms(@model y => -1 + x1 + x2) == Terms(@model y => x1 - 1 + x2) == Terms(@model y => x1 + x2 -1)

## can't subtract terms other than 1
@test_throws ErrorException Terms(@model y => x1 - x2)

t = Terms(@model y => x1 & x2)
@test t.terms == [:(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## `*` expansion
t = Terms(@model y => x1 * x2)
@test t.terms == [:x1, :x2, :(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## associative rule:
## +
t = Terms(@model y => x1 + x2 + x3)
@test t.terms == [:x1, :x2, :x3]

## &
t = Terms(@model y => x1 & x2 & x3)
@test t.terms == [:((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

## distributive property of + and &
t = Terms(@model y => x1 & (x2 + x3))
@test t.terms == [:(x1&x2), :(x1&x3)]

## FAILS: ordering of expanded interaction terms is wrong
## (only has an observable effect when both terms are categorical and
## produce multiple model matrix columns that are multiplied together...)
##
## t = Terms(@model y => (x2 + x3) & x1)
## @test t.terms == [:(x2&x1), :(x3&x1)]

## three-way *
t = Terms(@model y => x1 * x2 * x3)
@test t.terms == [:x1, :x2, :x3,
                  :(x1&x2), :(x1&x3), :(x2&x3),
                  :((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

## Interactions with `1` reduce to main effect.  All fail at the moment.
## t = Terms(@model y => 1 & x1)
## @test t.terms == [:x1]              # == [:(1 & x1)]
## @test t.eterms == [:y, :x1]

## t = Terms(@model y => (1 + x1) & x2)
## @test t.terms == [:x2, :(x1&x2)]    # == [:(1 & x1)]
## @test t.eterms == [:y, :x1, :x2]

end
