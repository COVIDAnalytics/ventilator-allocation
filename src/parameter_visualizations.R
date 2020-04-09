df_supply <- read.csv("../results/supply_integer_vent10.csv")
df_transfers <- read.csv("../results/transfers_integer_vent10.csv")

df_supply <- df_supply %>% mutate(Date = as.Date(Date),
                    Fmax = as.factor(Fmax))

df_transfers <- df_transfers %>% mutate(Date = as.Date(Day),
                                     Fmax = as.factor(Fmax))

last_shortfall <- df_supply %>% filter(Supply_Excess < 0) %>% pull(Date) %>% max()

 df_supply %>%
   filter(State== "US", DataSource == "ode") %>%
   filter(Date < as.Date("2020-05-01")) %>%
   filter(Buffer == 0.1)  %>%
   ggplot(aes(x = Date, y = -Supply_Excess)) +
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
 

 # df_supply %>%
 #   filter(State== "US", DataSource == "ihme") %>%
 #   filter(Date < as.Date("2020-05-01")) %>%
 #   filter(SurgeCorrection == 0.5)  %>%
 #   ggplot(aes(x = Date, y = -Supply_Excess)) +
 #   facet_grid(Buffer~Fmax, labeller = label_both) + 
 #   geom_line() +
 #   labs(title = "Shortfall Tradeoffs (SurgeCorrection = 0.5)")
 # 
 # df_transfers %>%
 #   group_by(Date, DataSource, Fmax, Buffer, SurgeCorrection) %>%
 #   summarize(Transfer_Count = n(), 
 #             Transfer_Volume = sum(Num_Units)) %>%
 #   filter(SurgeCorrection == 0.5)  %>%
 #   ggplot(aes(x = Date, y = Transfer_Volume)) +
 #   facet_grid(Buffer~Fmax, labeller = label_both) + 
 #   geom_line() +
 #   labs(title = "Transfer Volume (SurgeCorrection = 0.5)")
 
objs <- df_supply %>%
   filter(State== "US") %>%
   filter(Date < as.Date("2020-05-01")) %>%
   group_by(DataSource, Fmax, Buffer, SurgeCorrection) %>%
   summarize(Obj = sum(-Supply_Excess))


df_supply <- read.csv("../results/supply_integer.csv")
df_transfers <- read.csv("../results/transfers_integer.csv")
objs <- df_supply %>%
  filter(State== "US") %>%
  group_by(DataSource, Fmax, Buffer, SurgeCorrection) %>%
  summarize(Obj = sum(-Supply_Excess))

df_supply_10 <- read.csv("../results/supply_integer_vent10.csv")
df_transfers_10 <- read.csv("../results/transfers_integer_vent10.csv")

objs_10 <- df_supply_10 %>%
  filter(State== "US") %>%
  group_by(DataSource, Fmax, Buffer, SurgeCorrection) %>%
  summarize(Obj_10 = sum(-Supply_Excess))

left_join(objs, objs_10, on = c("DataSource", "Fmax", "Buffer", "SurgeCorrection")) %>%
  mutate(relative_loss = (Obj_10 - Obj)/Obj)

 