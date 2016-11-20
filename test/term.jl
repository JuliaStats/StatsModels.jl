module TermTest

using Base.Test
using StatsModels

import StatsModels.term

## Associative property
@test term(:(a+(b+c))) == term(:(a+b+c))
@test term(:((a+b)+c)) == term(:(a+b+c))
@test term(:(a&(b&c))) == term(:(a&b&c))
@test term(:((a&b)&c)) == term(:(a&b&c))

## Distributive property
@test term(:(a & (b+c))) == term(:(a&b + a&c))
@test term(:((a+b) & c)) == term(:(a&c + b&c))
@test term(:((a+b) & (c+d))) == term(:(a&c + a&d + b&c + b&d))
@test term(:(a & (b+c) & d)) == term(:(a&b&d + a&c&d))

## Expand * to main effects + interactions
@test StatsModels.Term{:+}(term(:(a*b))) == term(:(a+b+a&b))
@test sort!(StatsModels.Term{:+}(term(:(a*b*c)))) == term(:(a+b+c+a&b+a&c+b&c+a&b&c))
@test term(:(a + b*c)) == term(:(a + b + c + b&c))
@test term(:(a*b + c)) == term(:(a + b + a&b + c))

## printing terms:
@test string(term(:a)) == "a"
@test string(term(:(a+b))) == "+(a, b)"
@test string(term(:(a + a&b))) == "+(a, &(a, b))"
@test string(term(:(a+b | c))) == "(+(a, b) | c)"

end # module
