suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(stringr)
    library(tidyr)
})
source("./scripts/stage3/base.r")

stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

calculate_location <- function(kind_stack, error_root_stack, error_root_tree) {
    ifelse(
        !is.na(kind_stack),
        ifelse(error_root_stack == error_root_tree, "TB, Same Loc.", "TB, Diff. Loc."),
        "New"
    )
}


NO_FAULT <- c(NA, "Timeout", "Unsupported Operation")

deduplicated_borrowing_errors <- read_csv(file.path("./build/stage3/errors.csv"), show_col_types = FALSE) %>%
    filter(error_type_stack == "Borrowing Violation" | error_type_tree == "Borrowing Violation") %>%
    deduplicate()


stack_errors <- deduplicated_borrowing_errors %>%
    filter(error_type_stack == "Borrowing Violation") %>%
    select(kind_stack, error_type_stack) %>%
    group_by(kind_stack) %>%
    summarise(count = n())

tree_errors <- deduplicated_borrowing_errors %>%
    filter(error_type_tree == "Borrowing Violation") %>%
    select(kind_tree, error_type_tree) %>%
    group_by(kind_tree) %>%
    summarise(count = n())



test_results <- deduplicated_borrowing_errors %>%
    mutate(
        error_type_tree = ifelse(error_type_tree %in% c(NA, "Timeout", "Unsupported Operation"), "No Issue", ifelse(error_type_tree != "Borrowing Violation", "Non-Borrowing Issue", calculate_location(kind_stack, error_root_stack, error_root_tree)))
    ) %>%
    select(kind_stack, error_type_tree)

foreign_error_status <- deduplicated_borrowing_errors %>% select(kind_stack, is_foreign_error_stack) %>%
    group_by(kind_stack) %>%
    summarise(count = paste0(round(sum(is_foreign_error_stack) / n() * 100, 1), "% (", sum(is_foreign_error_stack), ")"))

test_results_table <- test_results %>%
    group_by(kind_stack, error_type_tree) %>%
    tally() %>%
    ungroup() %>%
    spread(error_type_tree, n, fill = 0) %>%
    # make a new column that is the sum across each column
    mutate(count = rowSums(select(., -kind_stack))) %>%
    # make every value a percentage of count for that row
    mutate_at(vars(-kind_stack, -count), ~ (paste0(round(. / count * 100, 0), "% (", ., ")"))) %>%
    select(kind_stack, count, `No Issue`, `Non-Borrowing Issue`, `TB, Diff. Loc.`, `TB, Same Loc.`, everything()) %>%
    arrange(desc(count)) %>%
    rename(Count = count, `SB Kind` = kind_stack) %>%
    write_csv(file.path("build/visuals/stacked_borrows.csv"))

