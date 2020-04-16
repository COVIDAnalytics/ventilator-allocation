library(tidyverse)

start_date = "2020-04-16"
end_date = "2020-06-01"

### IHME Predictions
df_ihme <- read.csv("../raw_data/ihme-2020_04_12.csv", stringsAsFactors = FALSE)

# state_list <- data.frame(State = state.name)
# write.csv(state_list, "../processed/state_list.csv", row.names = FALSE)

df_clean_ihme <- df_ihme %>%
  mutate(Day = as.Date(date)) %>%
  select(State = location_name, 
         Day,
         "Hospitalizations" = allbed_mean,
         "ICU" = ICUbed_mean, 
         "Ventilators" = InvVen_mean) %>%
  mutate_if(is.numeric, round) %>%
  filter(Day >= as.Date(start_date), Day < as.Date(end_date)) %>%
  filter(State %in% state.name)

write.csv(df_clean_ihme, paste0("../processed/predicted_ihme/AllStates.csv"), row.names = FALSE)


### ODE Predictions
df_ode <- read.csv("~/git/website/data/predicted/Allstates.csv", stringsAsFactors = FALSE)
df_clean_ode <- df_ode %>%
  rename(Ventilators = Active.Ventilated) %>%
  mutate(Day = as.Date(Day)) %>%
  filter(Day >= as.Date(start_date),  Day < as.Date(end_date)) %>%
  filter(State %in% state.name)
  
write.csv(df_clean_ode, paste0("../processed/predicted_ode/AllStates.csv"), row.names = FALSE)

