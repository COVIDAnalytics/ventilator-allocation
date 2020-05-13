using CSV, DataFrames
using DataFramesMeta
using Dates

include("$(@__DIR__)" * "/mip.jl")
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
# ------ Functions -------
# get list of states based on model choice
function load_states(model_choice="ode")
    states_all = CSV.read("processed/state_list.csv")[:State]
    if model_choice == "ode"
        df = CSV.read(download("https://raw.githubusercontent.com/COVIDAnalytics/website/master/data/predicted/Allstates.csv"))
        states = intersect(unique(df[:State]), states_all)
    elseif model_choice == "ihme"
        df = CSV.read("processed/predicted_ihme/AllStates.csv");
        states = intersect(unique(df[:State]), states_all)
    end
    return states
end

# read projection based on model choice
function load_projections(state; model="ode")
    if model == "ode"
        df = CSV.read(download("https://raw.githubusercontent.com/COVIDAnalytics/website/master/data/predicted/Allstates.csv"))
        rename!(df, Symbol("Active Ventilated") => :Ventilators)
        df = @where(df, :State .!= "District of Columbia")
    elseif model == "ihme"
        df = CSV.read("processed/predicted_ihme/AllStates.csv")
    end
    if state == "all"
        return df
    else
        df_sub = @where(df, :State .== state)
        df_sub = df_sub[:,2:end] # remove state name
    end
end

# 1. construct demand_matrix
function demand_matrix(model_choice)
    states = load_states(model_choice)
    state = states[1]
    df = load_projections(state, model = model_choice)
    df[:, Symbol("Vent_$state")] = df[:, :Ventilators]
    df = df[:, [:Day, Symbol("Vent_$state")]]
    for state in states[2:end]
        tmpdf = load_projections(state, model = model_choice)
        tmpdf[:, Symbol("Vent_$state")] = tmpdf[:, :Ventilators]
        tmpdf = tmpdf[:, [:Day, Symbol("Vent_$state")]]
        df = join(df, tmpdf, kind=:inner, on = :Day)
    end
    demand_days = df[:,1]
    demands = df[:,2:end] |> Matrix
    demands = Matrix(demands');
    return demands, demand_days
    end

# 2. load supply
function load_supply(states)
    df_supply = CSV.read("processed/ventilator_table_calculated.csv")
    base_supply = zeros(length(states))
    for (i, state) in enumerate(states)
        base_supply[i] = df_supply[df_supply[:, :STNAME].==state,:VentCalc_2019][1]
    end
    return base_supply
    end

# 3. load surge_supply
function load_surge_supply(demands, dates=[1], surge_amount=[0])
    surge_supply = zeros(size(demands, 2));
    d0=1
    for i in 1:size(dates,1)
        d1= dates[i]
        surge_supply[d0:d1] .= surge_amount[i]/(d1-d0+1);
        d0+=dates[i];
        end
    return surge_supply;
    end
# ------ End of Functions -------

# --- Wrapper function solving for transfers-----
function solve_transfers(surge_days=[1], surge_amount=[0])
	supply_table = DataFrame()
	transfers_table = DataFrame()

	for model_choice in ["ode", "ihme"]
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
	    distances_full = CSV.read("processed/state_distances.csv")
	    distances = @where(distances_full, [x in states for x in :Column1])[Symbol.(states)]
	    distances = distances |> Matrix;
	    # distances = select(distances, Not(:Column1)) |> Matrix;

	    #5. calculate delays
	    delays = 3 * ones(Int, size(distances));

		for min_stock in [0.8, 0.85, 0.9, 0.95, 1.0],
			alpha in [0.0, 0.05, 0.10, 0.20],
			surge_correction in [0.0, 0.5, 0.75, 0.9, 1.0]

            println("Parameters: model = $(model_choice), min_stock = $(min_stock), alpha = $alpha, surge_correction = $(surge_correction)")

		    supply, transfers = allocate_ventilators(demands, ceil.(base_supply .* 0.5),
		                                             ceil.(surge_supply .* surge_correction),
		                                             distances,
		                                             delays, only_send_excess=true,
		                                             minimum_stock_fraction = min_stock,
		                                             alpha=alpha, lasso=0.1,
		                                             max_ship_per_day = 3000.0,
		                                             OutputFlag=1, TimeLimit=600, MIPGap=0.05,
		                                             vent_days=10);
		    
		    ## Supply table
		    supply_long = supplies_to_long(supply, demands, states, demand_days, base_supply)
		    supply_long[:DataSource] = model_choice
		    supply_long[:Fmax] = 1-min_stock
		    supply_long[:Buffer] = alpha
		    supply_long[:SurgeCorrection] = surge_correction
		    supply_table = vcat(supply_table, supply_long)
		    
		    ## Transfer table
		    transfers_long = transfers_to_long(transfers, states, demand_days, surge = )
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
supply, transfers = solve_transfers()
CSV.write("$(@__DIR__)/../results/supply_integer_200416.csv", supply)
CSV.write("$(@__DIR__)/../results/transfers_integer_200416.csv", transfers)



