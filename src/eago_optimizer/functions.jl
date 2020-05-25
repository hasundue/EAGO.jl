"""
$(TYPEDEF)

An abstract super-type used for representing constraints built by EAGO's backend.
"""
abstract type AbstractEAGOConstraint end

"""

Computes the lower interval bound for `AbstractEAGOConstraint` representing an
inequality constraint.
"""
function lower_interval_bound end

"""

Computes a tuple representing the lower and upper interval bounds for a
`AbstractEAGOConstraint` representing an equality constraint.
"""
function interval_bound end


"""
$(TYPEDEF)

"""
struct AffineFunctionIneq <: AbstractEAGOConstraint
    terms::Vector{Tuple{Float64,Int}}
    constant::Float64
    len::Int
end

function lower_interval_bound(f::AffineFunctionIneq, y::NodeBB)

    terms = f.terms
    lo_bnds = y.lower_variable_bounds
    up_bnds = y.upper_variable_bounds

    lower_interval_bound = f.constant
    for i = 1:f.len
        coeff, indx = @inbounds terms[k]
        if coeff > 0.0
            lvb = @inbounds lo_bnds[indx]
            lower_interval_bound += coeff*lvb
        else
            uvb = @inbounds up_bnds[indx]
            lower_interval_bound += coeff*uvb
        end
    end

    return lower_interval_bound
end


"""
$(TYPEDEF)

"""
struct AffineFunctionEq <: AbstractEAGOConstraint
    terms::Vector{Tuple{Float64,Int}}
    constant::Float64
end

function interval_bound(s::SAF, y::NodeBB, flag::Bool)
    terms = f.terms
    lo_bnds = y.lower_variable_bounds
    up_bnds = y.upper_variable_bounds

    lower_interval_bound = f.constant
    upper_interval_bound = f.constant
    for i = 1:f.len
        coeff, indx = @inbounds terms[k]
        lvb = @inbounds lo_bnds[indx]
        uvb = @inbounds up_bnds[indx]
        if coeff > 0.0
            lower_interval_bound += coeff*lvb
            upper_interval_bound += coeff*uvb
        else
            lower_interval_bound += coeff*uvb
            upper_interval_bound += coeff*lvb
        end
    end

    return lower_interval_bound, upper_interval_bound
end


####
#### Quadratic Storage
####
"""
$(TYPEDEF)

Stores a general quadratic function with a buffer.
"""
mutable struct BufferedQuadraticIneq <: AbstractEAGOConstraint
    func::SQF
    buffer::OrderedDict{Int, Float64}
    saf::SAF
    nx::Int
end

"""
$(TYPDEF)

Stores a general quadratic function with a buffer.
"""
mutable struct BufferedQuadraticEq <: AbstractEAGOConstraint
    func::SQF
    buffer::OrderedDict{Int, Float64}
    saf::SAF
    nx::Int
end

#=
"""
$(FUNCTIONAME)

Stores a general quadratic function with a buffer.
"""
mutable struct BufferedNonlinear <: AbstractEAGOConstraint
    func
end
=#

####
#### Nonlinear Storage
####

struct EmptyNLPEvaluator <: MOI.AbstractNLPEvaluator
    _current_node::NodeBB
    has_nlobj::Bool
end
EmptyNLPEvaluator() = EmptyNLPEvaluator(NodeBB(),false)
set_current_node!(x::EmptyNLPEvaluator, n::NodeBB) = ()

MOI.features_available(::EmptyNLPEvaluator) = [:Grad, :Jac, :Hess]
MOI.initialize(::EmptyNLPEvaluator, features) = nothing
MOI.eval_objective(::EmptyNLPEvaluator, x) = NaN
function MOI.eval_constraint(::EmptyNLPEvaluator, g, x)
    @assert length(g) == 0
    return
end
MOI.eval_objective_gradient(::EmptyNLPEvaluator, g, x) = nothing
MOI.jacobian_structure(::EmptyNLPEvaluator) = Tuple{Int64,Int64}[]
MOI.hessian_lagrangian_structure(::EmptyNLPEvaluator) = Tuple{Int64,Int64}[]
function MOI.eval_constraint_jacobian(::EmptyNLPEvaluator, J, x)
    @assert length(J) == 0
    return
end
function MOI.eval_hessian_lagrangian(::EmptyNLPEvaluator, H, x, σ, μ)
    @assert length(H) == 0
    return
end

empty_nlp_data() = MOI.NLPBlockData([], EmptyNLPEvaluator(), false)

"""
$(TYPEDEF)

A structure used to hold objectives and constraints added to EAGO model.
The constraints generally aren't used for relaxations.

$(TYPEDFIELDS)
"""
Base.@kwdef mutable struct InputProblem

    # variables
    _variable_info::Vector{VariableInfo} = VariableInfo[]

    _variable_count::Int64 = 0

    # last constraint index added
    _last_constraint_index::Int = 0

    # linear constraints
    _linear_leq_constraints::Vector{Tuple{SAF, LT}} = Tuple{SAF, LT}[]
    _linear_geq_constraints::Vector{Tuple{SAF, GT}} = Tuple{SAF, GT}[]
    _linear_eq_constraints::Vector{Tuple{SAF, ET}} = Tuple{SAF, ET}[]

    _linear_leq_count::Int = 0
    _linear_geq_count::Int = 0
    _linear_eq_count::Int = 0

    # quadratic constraints
    _quadratic_leq_constraints::Vector{Tuple{SQF, LT}} = Tuple{SQF, LT}[]
    _quadratic_geq_constraints::Vector{Tuple{SQF, GT}} = Tuple{SQF, GT}[]
    _quadratic_eq_constraints::Vector{Tuple{SQF, ET}} = Tuple{SQF, ET}[]

    _quadratic_leq_count::Int = 0
    _quadratic_geq_count::Int = 0
    _quadratic_eq_count::Int = 0

    # conic constraints
    _conic_second_order::Vector{Tuple{VECOFVAR, MOI.SecondOrderCone}} = Tuple{VECOFVAR, MOI.SecondOrderCone}[]

    _conic_second_order_count::Int = 0

    # objectives
    _objective_sv::SV = SV(-1)
    _objective_saf::SAF = SAF(SAT[], 0.0)
    _objective_sqf::SQF = SQF(SAT[], SQT[], 0.0)
    _objective_type::ObjectiveType = UNSET

    # nlp constraints
    _nlp_data::MOI.NLPBlockData = empty_nlp_data()

    # attributes
    _optimization_sense::MOI.OptimizationSense = MOI.MIN_SENSE
end

#=
Holds specialized constraint functions used by EAGO to generate cuts
=#
Base.@kwdef mutable struct ParsedProblem
    _saf_leq::Vector{AffineFunctionIneq} = Vector{AffineFunctionIneq}[]
    _saf_eq::Vector{AffineFunctionEq} = Vector{AffineFunctionEq}[]
    _sqf_leq::Vector{BufferedQuadraticIneq} = Vector{BufferedQuadraticIneq}[]
    _sqf_eq::Vector{BufferedQuadraticEq} = Vector{BufferedQuadraticEq}[]
end

@enum(CI_ENUM, CI_UNSET, CI_QDLT, CI_QDET, CI_NLLT, CI_NLET, CI_SOC)

#=
"""
"""
mutable struct ConstraintIndexMap
    ineq_constraint_count::Int
    ineq_constraints_added::Int
    ci_added_type::Vector{CI_ENUM}
    ci_added_value::Vector{Int}
    ci_added_active::Vector{Bool}
    quadratic_le::Dict{Tuple{CI{SQF,LT},1}, CI{SAF,LT}}
    quadratic_ge::CI{SAF,LT}
    ci_quadratic_eq::CI{SAF,ET}
end

# get CI using conditional statement need map i -> enumerate CI_type
"""
Deletes cutting inequalities from relaxed optimizer and labels them as unset.
"""
function delete_cuts!(m::Optimizer)

    cmap = m._inner_constraints_map
    ci_added_value = cmap.ci_added_value
    ci_added_type = cmap.ci_added_type

    for i = 1:cmap.ineq_constraints_added

        ci_value = @inbounds ci_added_value[i]
        ci_type = @inbounds ci_added_type[i]

        if ci_type === CI_QDLT || ci_type === CI_QDET ||
           ci_type === CI_NLLT || ci_type === CI_NLET ||
           ci_type === CI_SOC

            MOI.delete(m.relaxed_optimizer, CI{SAF,LT}(ci_value))
            @inbounds ci_added_type[i] = CI_UNSET
        end
    end
    cmap.ineq_constraints_added = 0
    nothing
end
=#
