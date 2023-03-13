# v0.7.0

- Various minor but breaking changes in contrast coding: (#273)
  - `ContrastsMatrix` can use arbitrary `AbstractMatrix`es to store the actual
    contrasts matrix.
  - The number and order of type parameters on `ContrastsMatrix{C,M,T,U}` have
    changed (from `ContrastsMatrix{C,T,U}`, with the addition of the second type
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
