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

deduplicated_borrowing_errors %>% filter(kind_stack == "Invalid Framing")

stack_crates_total <- deduplicated_borrowing_errors %>%
    filter(error_type_stack == "Borrowing Violation") %>%
    filter(is_foreign_error_stack) %>%
    select(crate_name) %>%
    unique() %>%
    nrow()

stats <- stats %>% add_row(key = "stack_crates_total", value = stack_crates_total)

stack_errors <- deduplicated_borrowing_errors %>%
    filter(error_type_stack == "Borrowing Violation") %>%
    filter(is_foreign_error_stack)

num_crates_stack <- stack_errors %>%
    select(crate_name) %>%
    unique() %>%
    nrow()
stats <- stats %>% add_row(key = "stack_crate_total", value = num_crates_stack)

stack_counts <- stack_errors %>%
    select(kind_stack, crate_name) %>%
    group_by(kind_stack) %>%
    summarise(count = n(), crates = n_distinct(crate_name), n = paste0(n(), "/", n_distinct(crate_name)))

tree_outcomes <- stack_errors %>%
    mutate(error_type_tree = ifelse(error_type_tree %in% c(NA, "Timeout", "Unsupported Operation"), "None", ifelse(error_type_tree != "Borrowing Violation", "Non-TB", calculate_location(kind_stack, error_root_stack, error_root_tree))))

tree_outcome_counts <- tree_outcomes %>%
    group_by(kind_stack, error_type_tree) %>%
    summarize(count = n(), crates = n_distinct(crate_name), n = paste0(n(), "/", n_distinct(crate_name)))

tree_crate_counts <- tree_outcomes %>%
    group_by(kind_stack) %>%
    filter(error_type_tree != "TB, Diff. Loc.") %>%
    summarize(crates = n_distinct(crate_name)) %>%
    mutate(key = paste0("stack_error_no_tb_crates_", str_to_lower(str_replace_all(kind_stack, " ", "_"))), value = crates) %>%
    select(key, value)

stats <- stats %>% bind_rows(tree_crate_counts)

stack_error_total <- stack_counts %>%
    summarise(count = sum(count)) %>%
    pull(count)
stats <- stats %>% add_row(key = "stack_error_total", value = stack_error_total)
stack_crate_total <- stack_counts %>%
    summarise(count = sum(crates)) %>%
    pull(count)
stack_error_counts <- stack_counts %>%
    select(kind_stack, count) %>%
    mutate(key = paste0("stack_error_", str_to_lower(str_replace_all(kind_stack, " ", "_"))), value = count) %>%
    select(key, value)
stack_crate_counts <- stack_counts %>%
    select(kind_stack, crates) %>%
    mutate(key = paste0("stack_error_crates_", str_to_lower(str_replace_all(kind_stack, " ", "_"))), value = crates) %>%
    select(key, value)
stats <- stats %>%
    bind_rows(stack_error_counts) %>%
    bind_rows(stack_crate_counts)

tree_error_counts <- tree_outcome_counts %>%
    filter(error_type_tree != "TB, Same Loc.") %>%
    group_by(kind_stack) %>%
    summarise(value = sum(count)) %>%
    mutate(key = paste0("stack_error_no_tb_", str_to_lower(str_replace_all(kind_stack, " ", "_")))) %>%
    select(key, value)
tree_no_tb_total <- tree_error_counts %>%
    summarise(value = sum(value)) %>%
    pull(value)
stats <- stats %>% bind_rows(tree_error_counts)
stats <- stats %>% add_row(key = "stack_error_no_tb_total", value = tree_no_tb_total)

stats %>% write_csv(file.path("./build/visuals/sb.stats.csv"))
tree_outcome_counts %>%
    select(-crates, -count) %>%
    pivot_wider(names_from = error_type_tree, values_from = n) %>%
    inner_join(stack_counts %>% select(-count, -crates), by = c("kind_stack")) %>%
    rename(`Count` = n, `SB Error Type` = kind_stack) %>%
    select(`SB Error Type`, `Count`, `None`, `Non-TB`, `TB, Same Loc.`, `TB, Diff. Loc.`) %>%
    mutate_at(vars(-`SB Error Type`), ~ ifelse(is.na(.), "-", .)) %>%
    write_csv(file.path("build/visuals/stacked_borrows.csv"))
