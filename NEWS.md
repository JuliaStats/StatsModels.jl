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
