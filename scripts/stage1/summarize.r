library(dplyr)
library(readr)

stage1_input_dir <- file.path("./data/results/stage1")
stage1_output_dir <- file.path("./data/compiled/stage1")

test_counts <- read_csv(file.path(stage1_input_dir, "has_tests.csv"), col_names = c("crate_name", "test_count"), show_col_types = FALSE)

has_bytecode <- read_csv(file.path(stage1_input_dir, "has_bytecode.csv"), col_names = c("crate_name", "version"), show_col_types = FALSE)

has_tests_and_bytecode <- has_bytecode %>%
    inner_join(test_counts, by = c("crate_name")) %>%
    filter(test_count > 0) %>%
    select(crate_name, version) %>%
    write_csv(file.path(stage1_output_dir, "stage2.csv"), col_names = FALSE)

