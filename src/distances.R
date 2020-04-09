# install.packages("ggmap")
# install.packages("maps")
library(ggmap)
library(maps)

state_info <- data.frame(state = state.name,
                         coords = state.center) %>%
  arrange(state)

rownames(state_info) <- state_info$state

state_distances <- dist(state_info[,-1], method = "euclidean", diag = TRUE) %>%
  as.matrix()

write.csv(state_distances, "../processed/state_distances.csv")