using CSV, DataFrames
using DataFramesMeta
using Dates

include("$(@__DIR__)" * "/mip.jl")
include("$(@__DIR__)" * "/utils_load.jl")
include("$(@__DIR__)" * "/output_helpers.jl")

"""
    Main solver function
    Args:
        - model_choice: ode or ihme epidemic model
        - surge_days: list of dates when surge supply happens
        - surge_amount: list of surge amount at each surge day
        - lasso: the LASSO penalty coefficient on transfers (exact sparse will not scale)

    Retun:
        - supply: 
        - transfer:
"""

# --- Wrapper function solving for transfers-----
function solve_transfers(surge_days=[1], surge_amount=[0])
    supply_table = DataFrame()
    transfers_table = DataFrame()

    for model_choice in ["ihme", "ode"]
        states = load_states(model_choice)

        #1. load demand
        demands, demand_days = demand_matrix(model_choice)
        #2. load base_supply
        base_supply = load_supply(states)
        #3. load surge_supply
        surge_supply = 450.0 * ones(size(demands, 2))
        surge_supply[1:3] .= 0.0
        surge_supply[34:end] .= 0.0
        # surge_supply = load_surge_supply(demands, surge_days, surge_amount)

        #4. calculate distance
        distances_full = CSV.read("$(@__DIR__)/../processed/state_distances.csv")
        distances = @where(distances_full, [x in states for x in :Column1])[Symbol.(states)]
        distances = distances |> Matrix;
        # distances = select(distances, Not(:Column1)) |> Matrix;

        #5. calculate delays
        delays = 3 * ones(Int, size(distances));

        for min_stock in [0.8, 0.85, 0.9, 0.95],
            alpha in [0.0, 0.05, 0.10, 0.20],
            surge_correction in [0.5, 0.75, 0.9, 1.0]

            println("Parameters: model = $(model_choice), min_stock = $(min_stock), alpha = $alpha, surge_correction = $(surge_correction)")

            supply, transfers, surge_transfers = allocate_ventilators(demands, base_supply .* 0.5,
                                                     surge_supply .* surge_correction, distances,
                                                     delays, only_send_excess=true,
                                                     minimum_stock_fraction = min_stock,
                                                     alpha=alpha, lasso=0.1,
                                                     max_ship_per_day = 3000.0,
                                                     OutputFlag=0, TimeLimit=600, MIPGap=0.01,
                                                     vent_days=10);
            
            ## Supply table
            supply_long = supplies_to_long(supply, demands, states, demand_days, base_supply)
            supply_long[:DataSource] = model_choice
            supply_long[:Fmax] = 1-min_stock
            supply_long[:Buffer] = alpha
            supply_long[:SurgeCorrection] = surge_correction
            supply_table = vcat(supply_table, supply_long)
            
            ## Transfer table
            transfers_long = transfers_to_long(transfers, states, demand_days, surge = surge_transfers)
            transfers_long[:DataSource] = model_choice
            transfers_long[:Fmax] = 1-min_stock
            transfers_long[:Buffer] = alpha
            transfers_long[:SurgeCorrection] = surge_correction
            transfers_table = vcat(transfers_table, transfers_long)

            CSV.write("$(@__DIR__)/../results/supply_temp_$(model_choice).csv", supply_table)
            CSV.write("$(@__DIR__)/../results/transfers_temp_$(model_choice).csv", transfers_table)

        end
    end
    return supply_table, transfers_table
end

# --- End of wrapper function solving for transfers-----

# --- Main module ---

version = ARGS[1]
supply, transfers = solve_transfers()
CSV.write("$(@__DIR__)/../results/supply_$version.csv", supply)
CSV.write("$(@__DIR__)/../results/transfers_$version.csv", transfers)





