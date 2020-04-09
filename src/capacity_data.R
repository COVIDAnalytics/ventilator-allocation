library(tidyverse)

df_pop <- read.csv("../../danger_map/raw_data/co-est2019-alldata.csv", stringsAsFactors = FALSE)
df_ventilator <-  read.csv("../raw_data/ventilator_table.csv", stringsAsFactors = FALSE)

updated_counts <- df_ventilator %>%
  select(STNAME = X,  VentEst_2010 = Ventilator_Count)  %>%
  filter(STNAME != "U.S. (excluding  territories)")  %>%
  left_join(df_pop %>% filter(SUMLEV==40) %>% 
              select(STNAME, CENSUS2010POP, POPESTIMATE2019)) %>%
  mutate(PopGrowth = POPESTIMATE2019/CENSUS2010POP,
         VentCalc_2019  =  round(VentEst_2010*PopGrowth))

## Ventilator  totals  
sum(updated_counts$VentEst_2010)
sum(updated_counts$VentCalc_2019)

write.csv(updated_counts, "../processed/ventilator_table_calculated.csv", row.names = FALSE)

#' RECENT REFERENCNES ON COUNTS (generally refer to 2010 paper)
#' 62k: https://www.npr.org/sections/health-shots/2020/03/14/815675678/as-the-pandemic-spreads-will-there-be-enough-ventilators
#' addtl 92k "older models": https://sccm.org/Blog/March-2020/United-States-Resource-Availability-for-COVID-19