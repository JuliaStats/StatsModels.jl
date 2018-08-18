# an "inside out" kronecker-like product based on broadcasting reshaped arrays


# for a single row, some will be scalars, others possibly vectors.  for a whole
# table, some will be vectors, possibly some matrices

function kron_insideout(op::Function, args...)
    args = [reshape(a, ones(Int, i-1)..., :) for (i,a) in enumerate(args)]
    vec(broadcast(op, args...))
end

function row_kron_insideout(op::Function, args...)
    args = [reshape(a, size(a,1), ones(Int, i-1)..., :) for (i,a) in enumerate(args)]
    reshape(broadcast(op, args...), size(args[1],1), :)
end
