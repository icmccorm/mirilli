suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(stringr)
    library(tidyr)
})
errors <- read_csv(file.path("./build/stage3/errors.csv"), show_col_types = FALSE) %>%
    filter(memory_mode == "uninit")

final_bugs <- read_csv(file.path("./data/bugs.csv"), show_col_types = FALSE) %>%
    left_join(errors, by = c("crate_name", "version", "test_name")) %>%
    select(crate_name, version, location, test_name, location, issue, pull_request, commit, error_type_stack, action_stack, kind_stack, error_type_tree, action_tree, kind_tree)
