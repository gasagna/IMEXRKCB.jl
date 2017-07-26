export integrator, fwdmapgen, _propagate!

# """
#     forwmap!(g, A, T, Δt, scheme)

# Returns a function for the `T`-time forward map associated to the dynamical system
# defined by `g` and `A`. These two define the non-stiff and stiff part of the 
# equations, and obey the interface
    
#     g(::Real, x::T, ẋ::T)
#     A_mul_B!(out::T, A, x::T)
#     ImcA!(out::T, A, x::T)

# where `T` is any custom type. The code here is agnostic to this type, as long as
# there exists a method for `similar(::Type{T})`, so that the temporaries needed 
# can be generated internally without user intervention. 

# Integration is performed using the IMEXRK scheme defined by `scheme` using
# fixed time step `Δt`. The signature of the returned function `ret` is `ret(x)`, 
# which operates in place, overwriting its argument. The input argument `x` should
# be of a type with the storage defined in `scheme`.
# """

struct Integrator{G, At, Sc}
           g::G       # the non-stiff part. Potentially augmented with a quadrature function
           A::At      # the linear stiff part.
      scheme::Sc      # the scheme, with storage and RK implementation
          Δt::Float64 # the time step. Will be replaced by integration options
    function Integrator{G, At, Sc}(g::G, 
                                   A::At, 
                                   scheme::Sc, 
                                   Δt::Real) where {G, At, Sc}
        Δt > 0 || throw(ArgumentError("Δt must be greater than 0, got $Δt"))
        new(g, A, scheme, Δt)
    end
end

# Outer constructor
integrator(g, A, scheme::IMEXRKScheme, Δt::Real) =
    Integrator{typeof.((g, A, scheme))...}(g, A, scheme, Δt)

# If a quadrature function is provided, augment system and call outer constructor
integrator(g, A, q, scheme::IMEXRKScheme, Δt::Real) =
    integrator(aug_system(g, q), A, scheme, Δt)

# main entry points. Integrators are callable objects....
(I::Integrator)(x, T::Real)               = _propagate!(I.scheme, I.g, I.A, T, I.Δt, x, nothing)
(I::Integrator)(x, T::Real, mon::Monitor) = _propagate!(I.scheme, I.g, I.A, T, I.Δt, x, mon)

# returns a function `f(T)` that when called with a real argument
# T will return a function `g(x)` that maps the state `x` forward 
# in time by a time `T`.
fwdmapgen(I::Integrator) = T->(x->I(x, T))

# Integrator augmented with a quadrature function are callable with an additional argument.
(I::Integrator{<:AugmentedSystem})(x, q, T::Real)               = _propagate!(I.scheme, I.g, I.A, T, I.Δt, aug_state(x, q), nothing)
(I::Integrator{<:AugmentedSystem})(x, q, T::Real, mon::Monitor) = _propagate!(I.scheme, I.g, I.A, T, I.Δt, aug_state(x, q), mon)

# Main propagation function
@inline function _propagate!(scheme::IMEXRKScheme{S}, 
                             g, A, T::Real, Δt::Real, z::S, 
                             ms::Union{Monitor, Void}) where {S}
    T  > 0 || throw(ArgumentError("T must be greater than 0, got $T"))
    t = zero(Δt)
    while t < T
        # update monitors
        isa(ms, Monitor) && push!(ms, t, _state_quad(z))
        Δt⁺ = next_Δt(t, T, Δt)
        step!(scheme, g, A, t, Δt⁺, z)
        t += Δt⁺
    end
    z
end

# Return time step for current RK step. Becomes smaller than `Δt` in 
# case we need to hit the stopping `T` exactly.
function next_Δt(t, T, Δt::S)::S where S
    min(t + Δt, T) - t
end