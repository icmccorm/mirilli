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

create_error_candidates <- function(df) {
    df <- df %>% filter(!(error_type %in% c("LLI Internal Error", "Unsupported Operation"))) %>%
        mutate(full_error_text = str_replace(full_error_text, "alloc[0-9]+", "alloc")) %>%
        mutate(full_error_text = str_replace(full_error_text, "<[0-9]+>", "<>"))
    df <- df %>%
        group_by(crate_name, full_error_text, error_root) %>%
        mutate(error_id = cur_group_id()) %>%
        ungroup()
    max_group_id <- df %>% summarize(max_group_id = max(error_id)) %>% pull(max_group_id)
    df_dependent <- df %>% filter(str_detect(error_root, "^/root/.cargo/registry/src/")) 
    df <- df %>% filter(!(error_id %in% df_dependent$error_id))
    df_dependent <- df_dependent %>%    
        group_by(crate_name, full_error_text, error_root) %>%
        mutate(error_id = cur_group_id() + max_group_id) %>%
        ungroup()
    df %>% bind_rows(df_dependent) %>% select(error_id, crate_name, version, test_name, error_type, error_text, full_error_text)
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
stack_errors_labeled <- stack_errors %>%
    left_join(stack_errors_roots, by = c("crate_name", "test_name")) %>%
    create_error_candidates() %>%
    left_join(passed_in_tree_borrows, by = c("crate_name", "test_name")) %>%
    mutate(passed_in_tree_borrows = ifelse(is.na(passed_in_tree_borrows), FALSE, passed_in_tree_borrows)) %>%
    write_csv(file.path("./data/compiled/stage3/stack/errors.csv"))

stack_errors_labeled %>%
    group_by(error_id) %>%
    mutate(num_occurrences = n()) %>%
    slice(1) %>%
    ungroup() %>%
    write_csv(file.path("./data/compiled/stage3/stack/errors_unique.csv"))

tree_errors <- read_csv(file.path(root, "errors_tree.csv"), show_col_types = FALSE) %>%
    inner_join(all, by = c("crate_name")) 

tree_errors_roots <- read_csv(file.path(root, "tree_error_roots.csv"), show_col_types = FALSE)
tree_errors_labeled <- tree_errors %>%
    left_join(tree_errors_roots, by = c("crate_name", "test_name")) %>%
    create_error_candidates() %>%
    left_join(passed_in_stack_borrows, by = c("crate_name", "test_name")) %>%
    mutate(passed_in_stack_borrows = ifelse(is.na(passed_in_stack_borrows), FALSE, passed_in_stack_borrows)) %>%
    write_csv(file.path("./data/compiled/stage3/tree/errors.csv"))
tree_errors_labeled %>%
    group_by(error_id) %>%
    mutate(num_occurrences = n()) %>%
    slice(1) %>%
    ungroup() %>%
    write_csv(file.path("./data/compiled/stage3/tree/errors_unique.csv"))

all_errors <- read_csv(file.path("./data/compiled/stage2/stage3.csv"), show_col_types = FALSE, col_names = c("test_name", "crate_name", "version"))
timed_out_stack <- stack_borrow_status %>% filter(exit_code == 124)
timed_out_tree <- tree_borrow_status %>% filter(exit_code == 124)
timed_out <- timed_out_stack %>% bind_rows(timed_out_tree) %>% select(test_name, crate_name) %>% unique() %>% inner_join(all, by=("crate_name"))

































