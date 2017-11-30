module TestFormula

using Compat, StatsModels
using Compat.Test

# TODO:
# - grouped variables in formulas with interactions
# - is it fast?  Can expand() handle DataFrames?
# - deal with intercepts
# - implement ^2 for datavector's
# - support more transformations with I()?

## Formula parsing
import StatsModels: @formula, Formula, Terms

## totally empty
t = Terms(Formula(nothing, 0))
@test t.response == false
@test t.intercept == false
@test t.terms == []
@test t.eterms == []

## empty RHS
t = Terms(@formula(y ~ 0))
@test t.intercept == false
@test t.terms == []
@test t.eterms == [:y]
t = Terms(@formula(y ~ -1))
@test t.intercept == false
@test t.terms == []

## intercept-only
t = Terms(@formula(y ~ 1))
@test t.response == true
@test t.intercept == true
@test t.terms == []
@test t.eterms == [:y]

## terms add
t = Terms(@formula(y ~ 1 + x1 + x2))
@test t.intercept == true
@test t.terms == [:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## implicit intercept behavior:
t = Terms(@formula(y ~ x1 + x2))
@test t.intercept == true
@test t.terms == [:x1, :x2]
@test t.eterms == [:y, :x1, :x2]

## no intercept
t = Terms(@formula(y ~ 0 + x1 + x2))
@test t.intercept == false
@test t.terms == [:x1, :x2]

@test t == Terms(@formula(y ~ -1 + x1 + x2)) == Terms(@formula(y ~ x1 - 1 + x2)) == Terms(@formula(y ~ x1 + x2 -1))

## can't subtract terms other than 1
@test_throws ErrorException Terms(@formula(y ~ x1 - x2))

t = Terms(@formula(y ~ x1 & x2))
@test t.terms == [:(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## `*` expansion
t = Terms(@formula(y ~ x1 * x2))
@test t.terms == [:x1, :x2, :(x1 & x2)]
@test t.eterms == [:y, :x1, :x2]

## associative rule:
## +
t = Terms(@formula(y ~ x1 + x2 + x3))
@test t.terms == [:x1, :x2, :x3]

## &
t = Terms(@formula(y ~ x1 & x2 & x3))
@test t.terms == [:((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

## distributive property of + and &
t = Terms(@formula(y ~ x1 & (x2 + x3)))
@test t.terms == [:(x1&x2), :(x1&x3)]

## FAILS: ordering of expanded interaction terms is wrong
## (only has an observable effect when both terms are categorical and
## produce multiple model matrix columns that are multiplied together...)
##
## t = Terms(@formula(y ~ (x2 + x3)) & x1)
## @test t.terms == [:(x2&x1), :(x3&x1)]

## three-way *
t = Terms(@formula(y ~ x1 * x2 * x3))
@test t.terms == [:x1, :x2, :x3,
                  :(x1&x2), :(x1&x3), :(x2&x3),
                  :((&)(x1, x2, x3))]
@test t.eterms == [:y, :x1, :x2, :x3]

## Interactions with `1` reduce to main effect.  All fail at the moment.
## t = Terms(@formula(y ~ 1 & x1))
## @test t.terms == [:x1]              # == [:(1 & x1)]
## @test t.eterms == [:y, :x1]

## t = Terms(@formula(y ~ (1 + x1)) & x2)
## @test t.terms == [:x2, :(x1&x2)]    # == [:(1 & x1)]
## @test t.eterms == [:y, :x1, :x2]

@test dropterm(@formula(foo ~ 1 + bar + baz), :bar) == @formula(foo ~ 1 + baz)
@test dropterm(@formula(foo ~ 1 + bar + baz), 1) == @formula(foo ~ 0 + bar + baz)
@test_throws ArgumentError dropterm(@formula(foo ~ 0 + bar + baz), 0)
@test_throws ArgumentError dropterm(@formula(foo ~ 0 + bar + baz), :boz)
form = @formula(foo ~ 1 + bar + baz)
@test form == @formula(foo ~ 1 + bar + baz)
@test StatsModels.dropterm!(form, :bar) == @formula(foo ~ 1 + baz)
@test form == @formula(foo ~ 1 + baz)

# Incorrect formula separator
@test_throws ErrorException @formula(y => x + 1)

end
