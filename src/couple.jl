export coupled

# This is basically a 2-tuple. We could use Base.Tuple{Any, Any}, obtaining 
# most of the functionality except `similar` and `copy`, which we would need to
# overload. That would be type piracy, so we create our implementation.
# 
# There are two use cases in this library for this type:
# 1) a type that wraps the main state vector `a::A` augmented
#    with an appropriate object `b::B` used for quadrature integration.
#    Note that the type is immutable, hence if a scalar function need to be
#    integrated, the quadrature value is stored in a one-element vector, 
#    in the field `b`
# 2) a type to integrate a coupled system of equations, where the coupling
#    between the two parts is equivalent to a lower triangular coupling matrix.
#    This is useful for integrating the tangent equations jointly with the 
#    nonlinear equations.
struct Couple{A, B}
    a::A
    b::B
end

# constructors
coupled(a, b) = Couple(a, b)

# extract parts
@inline Base.first(ab::Couple) = ab.a
@inline Base.last( ab::Couple) = ab.b

# Operations are broadcasted to both parts
@generated function Base.Broadcast.broadcast!(f, dest::Couple, args...)
    quote
        $(Expr(:meta, :inline))
        broadcast!(f, first(dest), map(first, args)...)
        broadcast!(f,  last(dest), map(last,  args)...)
        return dest
    end
end

Base.similar(ab::Couple) = coupled(similar(first(ab)), similar(last(ab)))
Base.copy(   ab::Couple) = coupled(   copy(first(ab)),    copy(last(ab)))