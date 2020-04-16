library(tidyverse)
library(data.table)
library(RColorBrewer)

# install.packages("viridis")
library(viridis)
 
version = "0409"

## Read in data
df_supply <- read.csv(paste0("../results/supply_",version,".csv"), stringsAsFactors = FALSE)
df_transfers <- read.csv(paste0("../results/transfers_",version,".csv"), stringsAsFactors = FALSE)
df_baseline <- read.csv(paste0("../results/supply_baseline_",version,".csv"), stringsAsFactors = FALSE)

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

# Sensitivity Plots -------------------------------------------------------

df_supply %>%
  filter(State== "US", DataSource == "ode") %>%
  filter(Date < as.Date("2020-05-01")) %>%
  filter(Buffer == 0.1)  %>%
  ggplot(aes(x = Date, y = Shortage)) +
  facet_grid(SurgeCorrection~Fmax, labeller = label_both) + 
  geom_line() +
  labs(title = "Total Shortfall (Buffer = 0.1)")

df_transfers %>%
  group_by(Date, DataSource, Fmax, Buffer, SurgeCorrection) %>%
  summarize(Transfer_Count = n(), 
            Transfer_Volume = sum(Num_Units)) %>%
  filter(Buffer == 0.1)  %>%
  ggplot(aes(x = Date, y = Transfer_Volume)) +
  facet_grid(SurgeCorrection~Fmax, labeller = label_both) + 
  geom_line() +
  labs(title = "Transfer Volume (Buffer = 0.1)")


supply_summary <- df_supply %>%
  filter(State!="US") %>%
  filter(Date < as.Date("2020-05-01")) %>%
  group_by(DataSource, SurgeCorrection, Fmax, Buffer) %>%
  summarize(Days = n(),
            DaysToBalance = max(Date[Shortage > 0]) - min(Date),
            TotalShortage = sum(Shortage),
            ShortfallDays = sum(Shortage > 0),
            ShortageStates = uniqueN(State[Shortage > 0]),
            objShortage = sum(Shortage) + .25*sum(Shortage_Buffer))

transfers_summary <- df_transfers %>%
  filter(Date < as.Date("2020-05-01")) %>%
  group_by(DataSource, SurgeCorrection, Fmax, Buffer) %>%
  summarize(TransferUnits = sum(Num_Units),
            TransferUnits_StateLevel = sum(if_else(State_From=="Federal", 0, Num_Units)),
            ShipmentCount = n(),
            ShipmentCount_StateLevel = sum(State_From!="Federal"),
            objTransfers = sum(Distance_Contribution))

results <- inner_join(supply_summary, transfers_summary, 
                      by = c("DataSource", "SurgeCorrection", "Fmax", "Buffer"))

names(results)


# results %>% filter(Buffer == 0.1) %>%
#   ggplot(aes(x = objShortage, y = objTransfers, color = SurgeCorrection, shape = as.factor(Fmax))) +
#   facet_grid(.~DataSource, labeller = label_both, scales = "free_x") +
#   geom_point()

results %>%
  as.data.frame() %>%
  mutate(DataSource = if_else(DataSource=="ihme", "IHME", "DELPHI")) %>%
  filter(Buffer == 0.1) %>%
  ggplot(aes(x = Fmax, y = TransferUnits_StateLevel/TransferUnits,
             group = SurgeCorrection, color = SurgeCorrection)) + 
  facet_grid(.~DataSource, labeller = label_both, scales = "free_y") +
  geom_line() +
  theme_bw() + 
  theme(legend.position = "bottom") +
  labs(title = "Parameter Sensitivity: State vs. Federal Transfers",
       x = "Pooling Fraction",
       y = "Proportion of Transfers Initiated Between States",
       color="Surge Correction") 
