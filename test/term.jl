module TermTest

using Base.Test

import StatsModels.Term

## Associative property
@test Term(:(a+(b+c))) == Term(:(a+b+c))
@test Term(:((a+b)+c)) == Term(:(a+b+c))
@test Term(:(a&(b&c))) == Term(:(a&b&c))
@test Term(:((a&b)&c)) == Term(:(a&b&c))

## Distributive property
@test Term(:(a & (b+c))) == Term(:(a&b + a&c))
@test Term(:((a+b) & c)) == Term(:(a&c + b&c))
@test Term(:((a+b) & (c+d))) == Term(:(a&c + a&d + b&c + b&d))
@test Term(:(a & (b+c) & d)) == Term(:(a&b&d + a&c&d))

## Expand * to main effects + interactions
@test Term{:+}(Term(:(a*b))) == Term(:(a+b+a&b))
@test sort!(Term{:+}(Term(:(a*b*c)))) == Term(:(a+b+c+a&b+a&c+b&c+a&b&c))
@test Term(:(a + b*c)) == Term(:(a + b + c + b&c))
@test Term(:(a*b + c)) == Term(:(a + b + a&b + c))

## printing Terms:
@test string(Term(:a)) == "a"
@test string(Term(:(a+b))) == "+(a, b)"
@test string(Term(:(a + a&b))) == "+(a, &(a, b))"
@test string(Term(:(a+b | c))) == "(+(a, b) | c)"

end # module
