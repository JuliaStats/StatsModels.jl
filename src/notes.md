# Current status

`@formula` applies syntax re-writes and then re-writes symbols as `Term(s)` and
any non-`is_special` calls to `FunctionTerm`, with the first argument being the
highest level call and later arguments giving 

- anonymous function which takes one arg for every symbol in the original
  expression
- the names of the symbols for the arguments
- the original (quoted) expression that the term was generated from.

At this point, regular dispatch takes over: `+` captures a tuple of `Term`
arguments, `&(::Vararg{AbstractTerm})` an `InteractionTerm`, etc.  **This is the
main point of extension**: any call to `myfun` in the formula expression will
get `AbstractTerm` arguments if `is_special(Val(myfun)) == true`.

At the highest level, `~` creates a `FormulaTerm`, which just captures a (tuple
of) terms for the left and right-hand-sides.  From this, you create a schema
from a data source with `schema(::FormulaTerm, ::Data.Table)`, which is just a
`Dict` mapping variables `Term(var)`s to continuous/categorical terms.  "Hints"
can be provided (a la [JuliaDB.ML](http://juliadb.org/latest/manual/ml.html)),
in the form of

- A `AbstractContrasts` subtype
- `ContinuousTerm` or `CategoricalTerm` (with `DummyCoding` being the default
  contrasts).
  
Then, the schema is _applied_ to the formula with `apply_schema(f, schema)`,
which replaces `Term`s with `Continuous`/`CategoricalTerm`s.  Optinally, if the
schema is wrapped in a `FullRank` struct, `apply_schema` will check to see
whether categorical terms need to be promoted to `FullDummyCoding` in order to
generate a full-rank model matrix.

Finally, individual terms can be _called_ with a named tuple of data (either a
single row, or a "table" which is a named tuple of vectors) to convert that data
into model-friendly format.

# Left to do

* tests and rest of ModelFrame interface
* Interface with actual models (just used ModelFrame still)
* Example extension: mixed models (random effects)
* Wrapping numbers in formula macro
* kw arguments
* use "sink type" in schema

# Goals

## Backend-agnostic

Works with streaming (row-wise) or columnar data.

## Extensible

Allow package authors to add new types of terms and syntax (random effects),
using normal julia methods (generic functions).

## Minimal

Everything that's not a special DSL works like normal julia code.



# Importing ideas about Terms from StreamModels

At a very basic level, we have:
1. A data source
2. a schema (types and some metadata)
3. a model/predictor/feature/etc. matrix

A `Formula` describes an elaboration of how to transform a data source into
model matrix, a generalization of a schema?  Well, one kind of elaboration:
selecting, generating interactions, separating response and predictor
"schemas".  It's sort of a 2.5 step: sits in between the schema and the actual
model matrix.  (Or as a transformation of the schema itself...)

We can think of a `Term` as a way of mapping from a field in the data table to
some numerical representation.  Basics are `Continuous` and `Categorical`.
Formula adds `Interaction`, notion of response/predictor, and contrast coding.
But also (importantly) the ability to extend to new types of terms, too.

## What to include in macro vs. function and how

Example: how to control contrast coding?  In StreamModels there's no control
over it, everything is dummy coded, checked for redundancy, and promoted to full
rank (one-hot) dummy coding if there's lack of redundancy.  There's been a clear
demand to allow people to control this sort of thing (e.g., not promote to full
rank for certain models that already have an implicit intercept...).

Currently everything happens at the `set_schema!` stage, right?  There's a lot
of custom logic there for figuring out what kind of term to create, based on the
current term, context term, terms already seen, and the schema.  The most
natural place to put metadata about contrasts etc. is on the schema.  Or to
allow multiple sets of metadata, although how to use that in dispatch becomes
v. complicated.  So better to stick with a generic metadata store.  Which the
DataStreams.Schema _does_ support.

Maybe one way around this is to subtype Schema...as long as you can get types,
names, etc. then you should be good.  That seems like it might be unnecessary
though.  Although it would allow extensible construction of the familiar term
types.  But expressing that in a schema extension seems a little weird...might
also want to somehow include a model type as well in these methods.

**OR** use a clean-up pass (or allow for clean-up passes).  That maps on most
naturally to the sense of a formula sitting between schema and model matrix: you
just keep stacking bits on top to change the default behavior.

## What intermediate representation?

Want some kind of intermediate representation that says "generate numerical
representations for these N things".  That might be something like the current
Terms or ModelFrame: do we need a response?  etc.  But also include random
effects or other terms.  But there's additional transformation that should
happen: pull out all the terms on the RHS that go into the model matrix as one
collection, and leave the others.

...but we want to make it extensible.  maybe the best way to do this is through
methods.  so we provide `modelmatrix` and `modelresponse` methods on the
`Formula` struct which pull out the relevant terms and combine them, and others
can do whatever they'd like...`randomeffects` etc.

# Stages

## Parsing (syntactic re-writes)

To extend: dispatch `transform_formula_call_ex` or something like that on first
args of `:call`s (that aren't specials like `~`, `+`, `&`, and `*`).  Fallback
is to create `FunctionTerm` with anon function.  But packages can provide
methods for their own special syntax.  Would need to provide something that can
have `set_schema` called on it...

### Dealing with non-DSL calls

Could dispatch on the _actual type_ of the function called:

`term(f_orig::Function, f_anon::Function)` -> `FunctionTerm{F,G}(f_orig::F,
f_anon::G)`

Then packages override this with `term(f_orig::typeof(:|), ::Function)` to
generate own term type or whatever.

**Or** dispatch on the symbol itself:

`term(::Val{:|})` or something like that.

Actually I think it makes more sense to _separate_ the creation of the term and
the application of the syntactic transformations.  The question I guess is what
happens if you have nested things you want to handle "magically"

Actually the bigger question is how (and in what form) you pass the arguments of
the call on to the specific handler...because for something like random effects
you need to be able to treat the sub-expressions as formulae too.  Would it be
enough to pass the expression?  I don't think so.

We're doing something like

```
y ~ 1 + a*b + log(b) 
→
(ResponseTerm(:y), 
    PredictorTerm(InterceptTerm(), 
                  Term(:a), 
                  Term(:b),
                  InteractionTerm(:a, :b),
                  FunctionTerm(log, nt->log(nt.b), (:b, ))
```

And

```
y ~ 1 + a + (1+a | b)
→
ResponseTerm(:y),
PredictorTerm(InterceptTerm(),
              Term(:a)),
RanefTerm(PredictorTerm(InterceptTerm(), Term(:a)),
          GroupTerm(:b))
```

can we get that with `term(args...)?`  No, there needs to be some kind of
dispatch on the _head_ (e.g., `&(args...)` -> `Interaction(args...)`).

So that's the motivation for having something like `term_ex(head::Val,
ex::Expr)` which as a fallback creates an `Expr` for a `FormulaTerm`
constructor with the appropriate anonymous function.

The question THEN is whether there's any utility in dispatching on the function
that would have been called...what does that buy you?

Or maybe flip it around: what does generating _specific_ constructor expression
actually buy you?  How far can you get just dispatching on the args?  You'd have
to create a lot of un-used anonymous functions I guess, which isn't great.  But
it would be good to require as little macro-magic as possible (to allow, e.g.,
for programmatic formula creation).

Maybe a middle ground is to have an `is_special(::Val)`, which does two things:
1. controls whether to apply "special rules" to children
2. determines whether calls get converted to an anonymous function or not.

Or even better `is_special(s::Symbool)` falls back on `is_special(Val(s))` which
allows for extension.

This makes me think that it might be possible to just express this logic as a
generic rewrite rule: if it's a special call, and no other rules apply, replace
the expression with a `Term` constructor.  If it's not a special call, then
create a `FunctionTerm` constructor with the right anonymous function.

Actually then you can do something like `&(::Term, ::Term) =
InteractionTerm(args...)`

And `~(::LHS, ::RHS) = FormulaTerm(lhs, rhs)`?

`+` is trickier maybe...`+(::Term, ::Term, args...) = MatrixTerm`?  Need to deal
with the associativity...and "nonstandard terms".  `|(::LHS, ::RHS) =
RanefTerm(lhs, rhs)`. 


## Schema (data types)

Symbols (or EvalTerms?) → typed terms



## 

