function print_flows(transfers; day_range = 1:20)
    for day in day_range
        println("Day $day:")
        for (s2, state2) in enumerate(states), (s1, state1) in enumerate(states)
            if transfers[s1, s2, day] > 1e-16
                print("\t $state1" * ifelse(length(state1) < 7, "\t", "") * "\t => $state2" * ifelse(length(state2) < 12, "\t\t", "\t") * ": $(transfers[s1, s2, day])\n")
            end
        end
    end
end

function plot_netflow(supply, transfers, s)
    n_days = size(supply,2)
    i = findall(states .== s)[1]

    base_level = base_supply[i]
    inflow = sum(transfers[:,i,:], dims=1)[1,:]
    outflow = sum(transfers[i,:,:], dims=1)[1,:]

    p = plot(supply[i,:], title = "Net Flows: $s", label = "Supply", ylims = (0,maximum(vcat(supply[i,:],base_supply[i]))+10))
    plot!(p, [base_level], seriestype = :hline, lc = :black, label = "Base Stock")

    inflow_days = collect(1:n_days)[inflow.>0]
    outflow_days = collect(1:n_days)[outflow.>0]

    if length(inflow_days) > 0
        plot!(p, [inflow_days], seriestype = :vline, lc = :green, label = "Inflows")
    end

    if length(outflow_days) > 0
        plot!(p, [outflow_days], seriestype = :vline, lc = :red, label = "Outflows")
    end
    display(p)
end

## Functions to prepare data for saving

function transfers_to_long(transfers, states, days; surge = nothing)
    n_states = length(states)
    n_days = length(days)
    df_transfers = DataFrame(State_From = String[], State_To = String[], Day = Any[], Num_Units = Real[])
    for d in 1:n_days, i in 1:n_states, j in 1:n_states
        if transfers[i,j,d] > 1e-10
            push!(df_transfers, [states[i],states[j],days[d],transfers[i,j,d]])
        end
    end

    ## add surge if available 
    if surge != nothing 
        for d in 1:n_days, i in 1:n_states
            if surge[i,d] > 1e-10
                push!(df_transfers, ["Federal",states[i],days[d],surge[i,d]])
            end
        end
    end

    sort!(df_transfers, [:Day, order(:Num_Units, rev = true)])

    return df_transfers
end

function surge_transfers_to_long(surge, states, days)
    n_states = length(states)
    n_days = length(days)
    df_surge = DataFrame(State_From = String[], State_To = String[], Day = Any[], Num_Units = Real[])
    for d in 1:n_days, i in 1:n_states
        if surge[i,d] > 1e-10
            push!(df_surge, ["Federal",states[i],days[d],surge[i,d]])
        end
    end
    return df_surge
end


function supplies_to_long(supply, demands, states, days, base_supply)
    # prepare supply data
    df_supply = DataFrame(hcat(states, supply))
    names!(df_supply, vcat([:State], Symbol.(days)))
    df_supply_long = melt(df_supply, :State)
    names!(df_supply_long, [:Date, :Supply, :State])

    df_demand = DataFrame(hcat(states, demands))
    names!(df_demand, vcat([:State], Symbol.(days)))
    df_demand_long = melt(df_demand, :State)
    names!(df_demand_long, [:Date, :Demand, :State])

    df_full = join(df_supply_long, df_demand_long, on = [:State, :Date], kind = :left)
    df_full[:Supply_Excess] = df_full[:Supply] .- df_full[:Demand]
    
    # df_full = join(df_full, DataFrame(State = states, Base_Supply = base_supply), on = :State, kind = :left)

    df_full = select(df_full, [:State, :Date, :Supply_Excess, :Supply, :Demand])

    for d in Symbol.(days)
        df_sub = @where(df_full, :Date .== d, :State .!= "US")
        push!(df_full, ["US", d, sum(min.(df_sub[:Supply_Excess],0)), sum(df_sub[:Supply]), sum(df_sub[:Demand])])
    end

    return df_full
end


