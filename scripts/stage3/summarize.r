library(dplyr)
library(readr)
library(stringr)
library(tidyr)
stage3_root <- file.path("./data/compiled/stage3/")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}
deduplicate_error_text <- function(df) {
    df <- df %>%
        mutate(error_text = str_replace(error_text, "alloc[0-9]+", "alloc")) %>%
        mutate(error_text = str_replace(error_text, "<[0-9]+>", "<>"))
    return(df)
}

all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))

compile_errors <- function(dir) {
    # get the last directory in the path
    basename <- basename(dir)
    print(basename)

    stage3_root <- file.path("./data/compiled/stage3/", basename)

    if (!dir.exists(stage3_root)) {
        dir.create(stage3_root)
    }
    source_root <- file.path(dir)
    stack_errors <- file.path(dir, "errors_stack.csv") %>%
        read_csv(show_col_types = FALSE) %>%
        inner_join(all, by = c("crate_name")) %>%
        mutate(borrow_mode = "stack")

    stack_error_roots <- file.path(dir, "stack_error_roots.csv") %>%
        read_csv(show_col_types = FALSE)

    stack_meta <- file.path(dir, "stack_metadata.csv") %>%
        read_csv(show_col_types = FALSE)

    tree_errors <- file.path(dir, "errors_tree.csv") %>%
        read_csv(show_col_types = FALSE) %>%
        inner_join(all, by = c("crate_name")) %>%
        mutate(borrow_mode = "tree")

    tree_error_roots <- file.path(dir, "tree_error_roots.csv") %>%
        read_csv(show_col_types = FALSE)

    tree_meta <- file.path(dir, "tree_metadata.csv") %>%
        read_csv(show_col_types = FALSE)

    tree_errors <- tree_errors %>%
        full_join(tree_error_roots, by = c("crate_name", "test_name")) %>%
        full_join(tree_meta, by = c("crate_name", "test_name")) %>%
        deduplicate_error_text()

    stack_errors <- stack_errors %>%
        full_join(stack_error_roots, by = c("crate_name", "test_name")) %>%
        full_join(stack_meta, by = c("crate_name", "test_name")) %>%
        deduplicate_error_text()

    activated_tree <- tree_meta %>%
        inner_join(all, by = c("crate_name")) %>%
        filter(llvm_engaged == TRUE) %>%
        select(crate_name, test_name) %>%
        unique()
    activated_stack <- stack_meta %>%
        inner_join(all, by = c("crate_name")) %>%
        filter(llvm_engaged == TRUE) %>%
        select(crate_name, test_name) %>%
        unique()
    activated <- bind_rows(activated_tree, activated_stack) %>%
        unique()
    activated %>% write_csv(file.path(dir, "activated.csv"))
    test_failed_natively <- read_csv(file.path(dir, "status_native.csv"), col_names = c("exit_code", "crate_name", "test_name"), show_col_types = FALSE) %>%
        filter(exit_code != 0) %>%
        filter(exit_code != 124) %>%
        select(crate_name, test_name) %>%
        unique()
    missing_activation <- bind_rows(stack_errors, tree_errors) %>%
        anti_join(bind_rows(activated_tree, activated_stack), by = c("crate_name", "test_name")) %>%
        unique()
    missing_activation_ub <- missing_activation %>%
        filter(error_type %in% c("Undefined Behavior", "Stack Overflow"))
    missing_activation_erroneous_failure <- missing_activation %>%
        filter(error_type %in% c("Test Failed")) %>%
        anti_join(test_failed_natively, by = c("crate_name", "test_name"))
    missing_activation <- bind_rows(missing_activation_ub, missing_activation_erroneous_failure) %>%
        unique()
    write_csv(missing_activation, file.path(dir, "missing_activation.csv"))
    errors <- bind_rows(stack_errors, tree_errors) %>%
        filter(error_type != "Unsupported Operation") %>%
        filter(error_type != "LLI Internal Error") %>%
        select(crate_name, test_name, borrow_mode, error_type, error_text, error_root)
    errors_ub <- errors %>% filter(error_type != "Test Failed")
    errors_erroneous_failure <- errors %>%
        filter(error_type == "Test Failed") %>%
        anti_join(test_failed_natively, by = c("crate_name", "test_name"))
    errors <- bind_rows(errors_ub, errors_erroneous_failure) %>%
        pivot_wider(names_from = borrow_mode, values_from = c(error_type, error_text, error_root)) %>%
        group_by(crate_name, error_text_stack, error_text_tree, error_root_stack, error_root_tree) %>%
        mutate(error_id = cur_group_id()) %>%
        ungroup()
    return(errors)
}
zeroed <- compile_errors("./data/results/stage3/zeroed")
zeroed_deduplicated <- zeroed %>%
    group_by(error_id) %>%
    slice(1) %>%
    ungroup() %>%
    select(-error_id)
uninit <- compile_errors("./data/results/stage3/uninit")
uninit_deduplicated <- uninit %>%
    group_by(error_id) %>%
    slice(1) %>%
    ungroup() %>%
    select(-error_id)
zeroed_labelled <- zeroed %>% mutate(mode = "zeroed")
uninit_labelled <- uninit %>% mutate(mode = "uninit")
all_errors <- bind_rows(zeroed_labelled, uninit_labelled) %>%
    write_csv(file.path(stage3_root, "errors.csv"))

same_for_both <- zeroed_deduplicated %>%
    inner_join(uninit_deduplicated, by = join_by(crate_name, test_name, error_type_stack, error_type_tree, error_text_stack, error_text_tree, error_root_stack, error_root_tree)) %>%
    arrange(crate_name, test_name) %>%
    mutate(unique_error_id = paste0("U", row_number())) %>%
    inner_join(all, by = c("crate_name")) %>%
    select(unique_error_id, crate_name, version, test_name, error_type_stack, error_type_tree, error_text_stack, error_text_tree)
same_for_both %>% write_csv(file.path(stage3_root, "errors_unique.csv"))
different_for_uninit <- uninit_deduplicated %>%
    anti_join(same_for_both) %>%
    write_csv(file.path("./error_in_uninit.csv"))
different_for_zeroed <- zeroed_deduplicated %>%
    anti_join(same_for_both) %>%
    write_csv(file.path("./error_in_zeroed.csv"))
