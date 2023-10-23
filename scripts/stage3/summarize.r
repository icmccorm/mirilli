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
    df <- df %>% filter(!(error_type %in% c("LLI Internal Error", "Unsupported Operation")))
    df$full_error_text <- str_replace(df$full_error_text, "<[0-9]+>", "<>")
    df$full_error_text <- str_replace(df$full_error_text, "alloc[0-9]+", "alloc")
    df %>%
        group_by(crate_name, full_error_text, error_root) %>%
        slice(1) %>%
        ungroup()
}

root <- file.path("./data/results/stage3/")
stack_errors <- read_csv(file.path(root, "errors_stack.csv"), show_col_types = FALSE)
stack_errors_roots <- read_csv(file.path(root, "stack_error_roots.csv"), show_col_types = FALSE)
stack_errors <- stack_errors %>%
    left_join(stack_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors() %>%
    write_csv(file.path(stage3_root_stack, "errors_deduplicated.csv"))

tree_errors <- read_csv(file.path(root, "errors_tree.csv"), show_col_types = FALSE)
tree_errors_roots <- read_csv(file.path(root, "tree_error_roots.csv"), show_col_types = FALSE)
tree_errors <- tree_errors %>%
    left_join(tree_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors() %>%
    write_csv(file.path(stage3_root_tree, "errors_deduplicated.csv"))


