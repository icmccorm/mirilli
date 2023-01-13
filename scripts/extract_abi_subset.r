library(dplyr)
library(readr)

late_abis_path <- file.path("./data/compiled/late_abis.csv")

late_abis <- read_csv(
    late_abis_path,
    show_col_types = FALSE
)
early_abis_path <- file.path("./data/compiled/early_abis.csv")

early_abis <- read_csv(
    early_abis_path,
    show_col_types = FALSE
)

late_names <- late_abis %>% select(crate_name)
early_names <- early_abis %>% select(crate_name)
