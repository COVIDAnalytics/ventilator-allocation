library(tidyverse)
library(reshape2)

version = "200416"
model_choice = "ode"

## Read in data
df_supply <- read.csv(paste0("../results/supply_integer_",version,".csv"))
df_transfers <- read.csv(paste0("../results/transfers_integer_",version,".csv"))
df_baseline <- read.csv(paste0("../results/supply_baseline_",version,".csv"))

df_supply <- df_supply %>% mutate(Date = as.Date(Date), Supply_Excess = pmax(0,Supply_Excess*-1)) %>%
  rename(Shortage = Supply_Excess)

df_baseline <- df_baseline %>% mutate(Date = as.Date(Date), Supply_Excess = pmax(0,Supply_Excess*-1)) %>%
  rename(Shortage = Supply_Excess)

df_transfers <- df_transfers %>% mutate(Day = as.Date(Day), Fmax = as.factor(Fmax)) %>%
  rename(Date = Day)

## check that last_shortfall is earlier than our end date in the filter
df_baseline %>% filter(Shortage > 0) %>% pull(Date) %>% max()
df_supply %>% filter(Shortage > 0) %>% pull(Date) %>% max()

# Process Optimization Predictions ----------------------------------------

supply_parsed <- df_supply %>%
  filter(Date < as.Date("2020-05-08")) %>%
  rename(Param1 = Fmax, Param2 = Buffer, Param3 = SurgeCorrection) %>%
  filter(DataSource == model_choice) %>%
  select(-DataSource)

write.csv(supply_parsed, paste0("../results/state_supplies_table-",model_choice,".csv"),
                              row.names = FALSE)
write.csv(supply_parsed, paste0("../results/old/state_supplies_table-",version,"-",model_choice,".csv"),
          row.names = FALSE)

transfers_parsed <- df_transfers %>%
  mutate(Date = if_else(State_From == "Federal", Date - 3, Date)) %>%
  filter(Date < as.Date("2020-05-08")) %>%
  rename(Param1 = Fmax, Param2 = Buffer, Param3 = SurgeCorrection) %>%
  filter(DataSource == model_choice) %>%
  select(-DataSource) %>%
  arrange(Param1, Param2, Param3, Date, desc(Num_Units)) %>%
  mutate(Num_Units = if_else(Num_Units < 5, "<5", as.character(Num_Units)))


write.csv(transfers_parsed, paste0("../results/transfers_table-",model_choice,".csv"),
          row.names = FALSE)
write.csv(transfers_parsed, paste0("../results/old/transfers_table-",version,"-",model_choice,".csv"),
          row.names = FALSE)


# Process Baselines -------------------------------------------------------

baseline_parsed <- df_baseline %>%
  filter(Date < as.Date(""))
  filter(Date < as.Date("2020-06-01")) %>%
  rename(Param1 = Fmax, Param2 = Buffer, Param3 = SurgeCorrection) %>%
  filter(DataSource == model_choice) %>%
  select(-DataSource)

write.csv(baseline_parsed, paste0("../results/state_supplies_table_baseline-",model_choice,".csv"),
          row.names = FALSE)

write.csv(baseline_parsed, paste0("../results/old/state_supplies_table_baseline-",version,"-",model_choice,".csv"),
          row.names = FALSE)

baseline_parsed %>%
  filter(State == "US") %>%
  select(Date, Shortage, Supply, Demand) %>%
  melt(., id.vars=c("Date")) %>%
  ggplot(aes(x = Date, y = value, color = variable)) +
  geom_line() +
  labs(title = paste0("Baseline shortage (",model_choice,")"))

df_baseline %>% 
  group_by(Date, State == "US") %>%
  summarize(sum(Shortage))
  
