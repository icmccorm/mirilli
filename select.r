library(dplyr)
library(readr)
library(ggplot2)
library(tidyr)
options(dplyr.summarise.inform = FALSE)

all_path <- file.path("data/all.csv")
all <- read_csv(
    all_path,
    show_col_types = FALSE
)

downloads_path <- file.path("data/download_counts_1yr.csv")
downloads <- read_csv(
    downloads_path,
    show_col_types = FALSE
)

finished_early_path <- file.path("data/finished_early.csv")
finished_early <- read_csv(
    finished_early_path,
    show_col_types = FALSE
)

finished_late_path <- file.path("data/finished_late.csv")
finished_late <- read_csv(
    finished_late_path,
    show_col_types = FALSE
)

foreign_abis_path <- file.path("data/foreign_module_abis.csv")
foreign_abis <- read_csv(
    foreign_abis_path,
    show_col_types = FALSE
) %>% filter(abi == "C")

early_downloads <- finished_early %>% inner_join(downloads, by=c("name")) %>% inner_join(foreign_abis, by=c("name"))

early_downloads
top3 <- early_downloads %>%
  arrange(desc(num_downloads)) %>% 
  slice(1:3)
top3