library(tidyverse)

version = "0409"
df_supply <- read.csv(paste0("../results/supply-pareto_",version,".csv"), stringsAsFactors = FALSE) 
df_transfers <- read.csv(paste0("../results/transfers-pareto_",version,".csv"), stringsAsFactors = FALSE)

df_distances <- read.csv("../processed/state_distances.csv", stringsAsFactors = FALSE) %>%
  rbind(., c("Federal", rep(0,50))) %>%
  mutate_at(-1, as.numeric) %>%
  rename(State_From = X) %>%
  gather(key = "State_To", value = "Distance",
         setdiff(names(.), "State_From")) %>%
  mutate(State_To = gsub("\\."," ", State_To)) %>%
  mutate(Distance = 10 + Distance)


df_supply <- df_supply %>% mutate(Date = as.Date(Date), Supply_Excess = pmax(0,Supply_Excess*-1)) %>%
  rename(Shortage = Supply_Excess) %>%
  mutate(Fmax = as.factor(Fmax),
         Shortage_Buffer = pmax(0, (1+Buffer)*Demand - Supply - Shortage))

df_transfers <- df_transfers %>% mutate(Day = as.Date(Day)) %>%
  rename(Date = Day) %>%
  left_join(., df_distances, on = c("State_From", "State_To")) %>%
  mutate(Fmax = as.factor(Fmax),
         Distance_Contribution = Distance*Num_Units)

df_supply %>% filter(Shortage > 0) %>% pull(Date) %>% max()

df_supply %>% filter(Shortage_Buffer > 0) %>%
  select(Supply, Demand, Shortage, Shortage_Buffer)

supply_summary <- df_supply %>%
  filter(State!="US") %>%
  group_by(DataSource, SurgeCorrection, Fmax, Buffer, Lasso) %>%
  summarize(Days = n(),
            DaysToBalance = max(Date[Shortage > 0]) - min(Date),
            TotalShortage = sum(Shortage),
            ShortfallDays = sum(Shortage > 0),
            ShortageStates = uniqueN(State[Shortage > 0]),
            objShortage = sum(Shortage) + .25*sum(Shortage_Buffer))

transfers_summary <- df_transfers %>%
  group_by(DataSource, SurgeCorrection, Fmax, Buffer, Lasso) %>%
  summarize(TransferUnits = sum(Num_Units),
            TransferUnits_StateLevel = sum(if_else(State_From=="Federal", 0, Num_Units)),
            ShipmentCount = n(),
            ShipmentCount_StateLevel = sum(State_From!="Federal"),
            objTransfers = sum(Distance_Contribution))

results <- left_join(supply_summary, transfers_summary, 
                      by = c("DataSource", "SurgeCorrection", "Fmax", "Buffer", "Lasso")) %>%
  mutate_if(is.numeric , replace_na, replace = 0)

results %>% 
  ggplot(aes(x = TotalShortage, y = TransferUnits)) + 
  facet_grid(.~DataSource, labeller = label_both, scales = "free_x") +
  geom_point()
