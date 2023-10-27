library(dplyr)
library(readr)
library(stringr)

stage3_root <- file.path("./data/compiled/stage3")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}
stage3_root_stack <- file.path(stage3_root, "stack")
if (!dir.exists(stage3_root_stack)) {
    dir.create(stage3_root_stack)
}
stage3_root_tree <- file.path(stage3_root, "tree")
if (!dir.exists(stage3_root_tree)) {
    dir.create(stage3_root_tree)
}

filter_errors <- function(df) {
    df %>% filter(!(error_type %in% c("LLI Internal Error", "Unsupported Operation"))) %>%
        mutate(full_error_text = str_replace(full_error_text, "alloc[0-9]+", "alloc")) %>%
        mutate(full_error_text = str_replace(full_error_text, "<[0-9]+>", "<>")) %>%
        group_by(crate_name, full_error_text, error_root) %>%
        slice(1) %>%
        ungroup() %>%
        arrange(crate_name, error_root, full_error_text, test_name) %>%
        mutate(index = row_number())
}
all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names=c("crate_name", "version"))

root <- file.path("./data/results/stage3/")
tree_borrow_status <- read_csv(file.path(root, "status_tree.csv"),show_col_types = FALSE, col_name=c("exit_code", "crate_name", "test_name"))
stack_borrow_status <- read_csv(file.path(root, "status_stack.csv"),show_col_types = FALSE, col_name=c("exit_code", "crate_name", "test_name"))

passed_in_tree_borrows <- tree_borrow_status %>%
    filter(exit_code == 0) %>%
    select(crate_name, test_name) %>%
    distinct() %>%
    mutate(passed_in_tree_borrows = TRUE)
passed_in_stack_borrows <- stack_borrow_status %>%
    filter(exit_code == 0) %>%
    select(crate_name, test_name) %>%
    distinct() %>%
    mutate(passed_in_stack_borrows = TRUE)

stack_errors <- read_csv(file.path(root, "errors_stack.csv"), show_col_types = FALSE) %>%
    inner_join(all, by = c("crate_name")) 
stack_errors_roots <- read_csv(file.path(root, "stack_error_roots.csv"), show_col_types = FALSE)
stack_errors <- stack_errors %>%
    left_join(stack_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors() %>%
    select(crate_name, version, index, test_name, error_type, full_error_text, error_root, error_text) %>%
    left_join(passed_in_tree_borrows, by = c("crate_name", "test_name")) %>%
    mutate(passed_in_tree_borrows = ifelse(is.na(passed_in_tree_borrows), FALSE, passed_in_tree_borrows)) %>%
    write_csv(file.path(stage3_root_stack, "errors_deduplicated.csv"))

tree_errors <- read_csv(file.path(root, "errors_tree.csv"), show_col_types = FALSE) %>%
    inner_join(all, by = c("crate_name")) 
tree_errors_roots <- read_csv(file.path(root, "tree_error_roots.csv"), show_col_types = FALSE)
tree_errors <- tree_errors %>%
    left_join(tree_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors() %>%
    select(crate_name, version, index, test_name, error_type, full_error_text, error_root, error_text) %>%
    left_join(passed_in_stack_borrows, by = c("crate_name", "test_name")) %>%
    mutate(passed_in_stack_borrows = ifelse(is.na(passed_in_stack_borrows), FALSE, passed_in_stack_borrows)) %>%
    write_csv(file.path(stage3_root_tree, "errors_deduplicated.csv"))






























