# v0.8.0

- Term collections are now `Vector{AbstractTerm}` instead of tuples (#354).
  This is a breaking change for package developers; user-facing `@formula`
  syntax and `modelcols`/`modelmatrix` are unchanged.  The motivation is
  compile latency: with tuples, every distinct number and order of terms in a
  formula triggered a fresh specialization of the whole `apply_schema`,
  `modelcols`, `coefnames`, etc. pipeline, so fitting a model with a
  never-seen formula cost ~0.1-0.8s of compilation.  With vectors, this drops
  to milliseconds.

  - `+` on terms returns a `Vector{AbstractTerm}`, and `&` distributes over
    vectors of terms instead of tuples.

  - `InteractionTerm` and `MatrixTerm` are no longer parametric: both store
    their terms in a `terms::Vector{AbstractTerm}` field.  The constructors
    still accept any iterable of terms (including tuples), so
    `InteractionTerm((a, b))` keeps working.  Code that dispatched on the
    element types, e.g. `InteractionTerm{<:NTuple{N,CategoricalTerm}}`, must
    switch to a run-time check such as
    `all(t -> t isa CategoricalTerm, it.terms)`.

  - `TupleTerm` is removed.  Methods that took a `TupleTerm` should take an
    `AbstractVector{<:AbstractTerm}` instead.  `TermOrTerms` is now
    `Union{AbstractTerm, AbstractVector{<:AbstractTerm}}`.

  - `collect_matrix_terms` returns a `Vector{AbstractTerm}` (with the
    `MatrixTerm` first) in the mixed matrix/non-matrix case, and `modelcols`
    on a vector of terms returns a vector of the per-term columns.

  - `apply_schema` on a vector of terms applies the schema term by term, from
    left to right, and combines the results with `+`, so duplicates are
    dropped and terms that expand to several terms are flattened.

  - An empty vector of terms is valid everywhere a vector of terms is: it
    yields an empty `MatrixTerm` of width 0 whose `modelcols` is a matrix with
    no columns, like `InterceptTerm{false}`.  Constructing an
    `InteractionTerm` with no terms throws an `ArgumentError`.

  - `FormulaTerm`, `InteractionTerm`, and `MatrixTerm` now have content-based
    `==` and `hash`, since the default field-identity comparison no longer
    holds with vector fields, and `FunctionTerm` gains a `hash` consistent
    with its existing `==`.  As a consequence, formulas compare equal after
    `apply_schema` when their terms do, and hash-based deduplication
    (`unique`, `Set`) works for formulas containing function calls.

- The right-hand side of a formula built with `~` or `@formula` is always a
  `Vector{AbstractTerm}`, even when it contains a single term (#354).
  Previously `@formula(y ~ x).rhs` was the bare term `x`; it is now `[x]`.
  This removes the lone-term special case, so code that handled both a term
  and a tuple on the right-hand side can handle a vector only.  The left-hand
  side is still a bare term, and after `apply_schema` the right-hand side is
  still collected into a single `MatrixTerm` when every term is a matrix
  term, so the `(y, X)` returned by `modelcols(f, data)` is unchanged.  The
  same applies to `+` (`a + a` is now `[a]` rather than `a`) and to
  `apply_schema` on a vector of terms, which returns a vector even when only
  one term remains.

# v0.7.0

- `FunctionTerm` rework (#183)

  - `FunctionTerm{F,Args}` now stores the called function, the original
    expression, and the arguments (wrapped in `Term`/`ConstantTerm`s).  Package
    maintainers that rely on `FunctionTerm` representations to implement special
    syntax will need to substantially update that existing code.  This may be as
    simple as defining a run-time method for `my_fun` that takes in
    `AbstractTerm`s and returns `MyTermType` with an accompanying method for
    `apply_schema(::FunctionTerm{typeof(my_fun)}, ...` that recursively applies
    the schema to the captured arguments and calls the run-time method:
    
    ```julia
    my_fun(args::AbstractTerm...) = MyTermType(args...)

    function apply_schema(t::FunctionTerm{typeof(my_fun)}, schema, Ctx)
        args = apply_schema.(t.args, Ref(schema), Ref(Ctx))
        return t.f(args...)
    end
    ```
    
    However, if the `@formula` syntax (i.e., `&` for interaction, `+` for union,
    etc.) should apply _within_ the call to `my_fun`, then care needs to be
    taken to un-protect any nested calls as necessary (although this is only
    likely to be a concern if the special syntax occurs as a _child_ of another,
    non-special call).  The above recommendation may still Just Work™ but some
    thorough testing is recommended.

  - It is now possible (although not exactly _convenient_) to construct
    `FunctionTerm`s at run-time (i.e., outside of a `@formula` macro).  See [the
    tests](https://github.com/JuliaStats/StatsModels.jl/blob/623906fa27ce84a1a2a5e62014d6b9f58d2ccd47/test/protect.jl#L23-L24)
    for an example of how this might be accomplished in practice.

  - Special syntax is introduced to `protect` function calls from the usual
    `@formula` interpretation (i.e., to treat `+` as addition, use `protect(a +
    b)`) and `unprotect` calls, switching back to interpreting them as
    `@formula` specials (i.e., to take the logarithm of an interaction term, use
    `log(unprotect(a & b))`).

- Various minor but breaking changes in contrast coding: (#273)

  - `ContrastsMatrix` can use arbitrary `AbstractMatrix`es to store the actual
    contrasts matrix.

  - The number and order of type parameters on `ContrastsMatrix{C,M,T,U}` have
    changed (from `ContrastsMatrix{C,T,U}`), with the addition of the second type
    parameter `M` capturing the type of the contrasts matrix.  This is unlikely
    to affect users but package developers must update anywhere they are
    specializing on `T` or `U` (which capture the `eltype` of the term names and
    levels, respectively).

  - All `AbstractContrasts` now have keyword argument constructors.

  - When constructing `HypothesisCoding` instances, the `labels=` and `levels=`
    kwargs are now mandatory.

  - `ContrastsCoding` is no longer exported (previously, a warning was issue
    that this export is deprecated and is discouraged).

  - The un-used `base=` kwarg for `SeqDiffCoding` has been removed (previously
    was a deprecation warning).
