library(dplyr)
library(readr)
library(ggplot2)
library(tidyr)
options(dplyr.summarise.inform = FALSE)

foreign_abis_path <- file.path("redo/foreign_module_abis.csv")
foreign_abis <- read_csv(
    foreign_abis_path,
    show_col_types = FALSE
) %>% select(name, abi) %>% filter(!abi %in% c("Rust"))

grouped <- foreign_abis %>% group_by(name) %>% summarize(n=n())
grouped
#the maximum number of abis is 3

max(grouped$n)

foreign_abis %>% group_by(abi) %>% summarize(abi, n = n()) %>% unique()

foreign_abis %>% select(name) %>% unique %>% nrow