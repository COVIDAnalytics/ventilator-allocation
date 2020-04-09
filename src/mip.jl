# Note: this is using JuMP 0.18.5 - we can switch to the more recent JuMP if necessary
using JuMP, Gurobi

global GUROBIENV = Gurobi.Env()

"""
    Helper function, compute shortfall cost under no pooling
    See parameter descriptions in docstring for allocate_ventilators
"""
function shortfall_without_pooling(demands::Matrix, base_supply::Vector, alpha::Real, rho::Real)
    D = size(demands, 2)
    results = zeros(length(base_supply))
    for d = 1:D
        results .+= max(0,
                        demands[:, d] .- base_supply .+ rho .* alpha .* demands[:, d],
                        rho .* (demands[:, d] .* (1 + alpha) .- base_supply))
    end
    return results
end

"""
    Main allocation function
    Args:
        - demands:       a (# states) × (# days) matrix; element (i, j) is the demand for ventilators in state i for period j
        - env:           Gurobi Environment to minimize the number of annoying license messages
        - base_supply:   the initial supply of ventilators in each state
        - surge_supply:  the total amount of ventilators that can be added into the system by FEMA on each day
        - distances:     the matrix of distances between all pairs of states
        - delays:        the matrix of integer delays required to ship between all pairs of states
    Keyword args:
        - lasso:         the LASSO penalty coefficient on transfers (exact sparse will not scale)
        - alpha:         robustness buffer above the demand
        - rho:           relative cost of missing buffer demand vs. real demand
        - minimum_stock_fraction: fraction of base ventilator stock that cannot leave a state
        - max_ship_per_day: maximum number of ventilators that can be sent out by a state per day
        - easy_incentive: whether to guarantee hat states will be no worse off by participating
        - gurobiargs:    Gurobi keyword arguments
"""
function allocate_ventilators(demands::Matrix, base_supply::Vector, surge_supply::Vector, 
                              distances::Matrix, delays::Matrix{Int}, env=GUROBIENV;
                              lasso::Real=0.0, minimum_stock_fraction::Real = 0.0,
                              only_send_excess::Bool=false, easy_incentive::Bool=false, max_ship_per_day::Real = 3000.0,
                              vent_days::Int = 0, alpha::Real=0.1, rho::Real=0.25,
                              lp_relaxation::Bool=false,
                              gurobiargs...)
    # numbers of days
    D = size(demands, 2)
    # number of states
    S = size(demands, 1)
    model = Model(solver=GurobiSolver(env; gurobiargs...))
    # Supply of ventilators in each state, at each time, cannot go below a certain threshold
    @variable(model, supply[s=1:S, 0:D] >= floor.(minimum_stock_fraction * base_supply[s]))
    # amount of flow sent from state i to state j on day d
    if lp_relaxation
        @variable(model, flow[1:S, 1:S, 1:D] >= 0)
        @variable(model, surge[1:S, 1:D] >= 0)
    else
        @variable(model, flow[1:S, 1:S, 1:D] >= 0, Int)
        @variable(model, surge[1:S, 1:D] >= 0, Int)
    end
    # shortfall of demand in each state
    @variable(model, shortfall[1:S, 1:D] >= 0)
    # buffer for shortage in each state
    @variable(model, buffer[1:S, 1:D] >= 0)
    # additional ventilators provided to each state from national surge supply
    
    # initial supply
    @constraint(model, [s=1:S], supply[s, 0] == base_supply[s])
    # Surge supply constraints
    @constraint(model, [d=1:D], sum(surge[s, d] for s=1:S) <= surge_supply[d])
    # no self-flows
    @constraint(model, [s=1:S, d=1:D], flow[s, s, d] == 0)
    # flow constraints
    @constraint(model, [s=1:S, d=1:D],
                supply[s, d] == supply[s, d - 1]                            # amount yesterday
                                + surge[s, d] # surge supply
                                - sum(flow[s, dest, d] for dest = 1:S) # shipments leaving today
                                + sum(flow[orig, s, d - delays[orig, s]] for orig = 1:S if d > delays[orig, s])) # incoming
    # shortfall
    @constraint(model, [s=1:S, d=1:D], shortfall[s, d] + supply[s,d] + buffer[s,d] >= demands[s,d] * (1 + alpha))
    @constraint(model, [s=1:S, d=1:D], shortfall[s, d] + supply[s,d] >= demands[s, d])
    # max size of total outward transfers
    @constraint(model, [s=1:S, d=1:D], sum(flow[s, out, d] for out = 1:S) <= max_ship_per_day)

    # can't go below inflow amount within 10 days: if receive X on day d, must have at least X supply for day d+1,...d+10
    if vent_days != 0
        # @constraint(model, [s=1:S, d=1:D-vent_days, d_lag=d+1:d+vent_days], sum(flow[i, s, d] for i = 1:S) <= supply[s, d_lag])
        @constraint(model, [s=1:S, d=2:D],
                    sum(flow[i, s, d_in] for i = 1:S, d_in=max(d-vent_days,1):(d-1)) +
                    sum(surge[s, d_in] for d_in=max(d-vent_days,1):(d-1)) <= supply[s, d])
    end
 
    if easy_incentive
        max_shortfalls = shortfall_without_pooling(demands, base_supply, alpha, rho)
        @constraint(model, [s=1:S], sum(shortfall[s, d] for d=1:D) <= max_shortfalls[s])
    end
        
    if only_send_excess
        # binary variables that indicate whether there is a shortfall
        @variable(model, has_shortfall[1:S, 1:D], Bin)
        # big-M constraint
        @constraint(model, [s=1:S, d=1:D], shortfall[s, d] + buffer[s, d] <= demands[s, d] * (1 + alpha) * has_shortfall[s, d])
        # no flow if shortfall
        @constraint(model, [s=1:S, d=1:D], sum(flow[s, out, d] for out = 1:S) <= (1 - has_shortfall[s, d]) * max_ship_per_day)
    end
    
    # objective: minimize shortfall subject to LASSO penalty on flows
    @objective(model, Min, sum(shortfall[s, d] for s=1:S, d=1:D) +
                           rho * sum(buffer[s, d] for s=1:S, d=1:D) +
                           lasso * (sum((distances[s1, s2] + 10) * flow[s1, s2, d] for s1 = 1:S, s2 = 1:S, d = 1:D)
                                        + 10 * sum(surge[s, d] for s=1:S, d=1:D)))

    solve(model)
    supply_levels = [getvalue(supply[s, d]) for s=1:S, d=1:D]
    transfers = [getvalue(flow[s1, s2, d]) for s1=1:S, s2=1:S, d=1:D]
    surge = [getvalue(surge[s, d]) for s=1:S, d=1:D]
    return supply_levels, transfers, surge
end
