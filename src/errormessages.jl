
"""
This is borrowed from [DataFrames.jl](). 
Return between 0 and 2 names from `colnames` closest to `name`.
`colnames` : some iterable collection of symbols
"""
function fuzzymatch(colnames, name::Symbol)
    ucname = uppercase(string(name))
    dist = [(levenshtein(uppercase(string(x)), ucname), x) for x in colnames]
    sort!(dist)
    c = [count(x -> x[1] <= i, dist) for i in 0:2]
    maxd = max(0, searchsortedlast(c, 8) - 1)
    return [s for (d, s) in dist if d <= maxd]
end

"""
Return a nice-ish error message if the Symbol `name` isn't a column name in `table`, otherwise a zero-length string.
"""
function checkcol(table, name::Symbol)
    i = Tables.columnindex(table, name)
    if i == 0 # if no such column
        names = Tables.columnnames(table)
        nearestnames = join(fuzzymatch(names, name),", " )
        return "There isn't a variable called '$name' in your data; the nearest names appear to be: $nearestnames"
    end

    nrows = length(Tables.getcolumn(table, name))
    if nrows == 0
        return "Column $name is empty."
    end

    return ""
end

"""
Check that each name in the given model `f` exists in the data source `t` and return a message if not. Return a zero string otherwise.
`t` is something that implements the `Tables` interface.
"""
function checknamesexist(f::FormulaTerm, t)
    if ! Tables.istable(t)
        throw(ArgumentError( "$(typeof(t)) isn't a valid Table type" ))
    end
    for n in StatsModels.termvars(f)
        msg = checkcol(t, n)
        if msg != ""
            return msg
        end
    end    
    return ""
end
