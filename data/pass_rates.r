library(dplyr)
library(readr)
library(tidyr)
options(dplyr.summarise.inform = FALSE)

all_path <- file.path("./data/all.csv")
all <- read_csv(
    all_path,
    show_col_types = FALSE
)

early_path <- file.path("./data/compiled/finished_early.csv")
early <- read_csv(
    early_path,
    show_col_types = FALSE
)
late_path <- file.path("./data/compiled/finished_late.csv")
late <- read_csv(
    late_path,
    show_col_types = FALSE
)
failed_path <- file.path("./data/results/failed_compilation.csv")
failed <- read_csv(
    failed_path,
    show_col_types = FALSE
)
total <- all %>% nrow
passed_early <- early %>% nrow
failed_early <- total - passed_early
passed_late <- late %>% nrow
failed_late <- passed_early - passed_late
compiled <- total - (failed %>% nrow)

print(paste("Total crates: ", total))
print(paste("Passed Early: ", passed_early))
print(paste("Failed Early: ", failed_early))
print(paste("Passed Late: ", passed_late))
print(paste("Failed Late: ", failed_late))
print(paste("Finished compilation: ", compiled))
print(paste("Failed compilation: ", total - compiled))
