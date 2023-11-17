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
valid_error_type <- function(type) {
    (type != "Unsupported Operation" & type != "LLI Internal Error" & type != "Timeout")
}
errored_exit_code <- function(exit_code) {
    exit_code != 0 & exit_code != 124
}

prepare_errors <- function(dir, type) {
    error_path <- file.path(dir, paste0("errors", "_", type, ".csv"))
    root_path <- file.path(dir, paste0(type, "_error_roots.csv"))
    meta_path <- file.path(dir, paste0(type, "_metadata.csv"))
    errors <- read_csv(error_path, show_col_types = FALSE) %>%
        inner_join(all, by = c("crate_name"))
    error_roots <- read_csv(root_path, show_col_types = FALSE)
    error_rust_locations <- errors %>%
        select(crate_name, test_name, error_location_rust) %>%
        rename(error_root = error_location_rust) %>%
        filter(!is.na(error_root))
    error_roots <- error_roots %>%
        anti_join(error_rust_locations, by = c("crate_name", "test_name")) %>%
        bind_rows(error_rust_locations)
    meta <- read_csv(meta_path, show_col_types = FALSE)
    errors <- errors %>%
        full_join(error_roots, by = c("crate_name", "test_name")) %>%
        full_join(meta, by = c("crate_name", "test_name")) %>%
        deduplicate_error_text()
    exit_codes <- read_csv(file.path(dir, paste0("status_", type, ".csv")), col_names = c("exit_code", "crate_name", "test_name"), show_col_types = FALSE)
    errors <- errors %>%
        full_join(exit_codes, by = c("crate_name", "test_name")) %>%
        mutate(error_type = if_else(exit_code == 124, "Timeout", error_type)) %>%
        mutate(borrow_mode = type)
    return(errors)
}

all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))

compile_errors <- function(dir) {
    basename <- basename(dir)
    print(basename)
    stack_errors <- prepare_errors(dir, "stack")
    tree_errors <- prepare_errors(dir, "tree")
    status_col_names <- col_names <- c("exit_code", "crate_name", "test_name")
    native_comp_status <- read_csv(file.path(dir, "status_native_comp.csv"), col_names = status_col_names, show_col_types = FALSE) %>%
        rename(native_comp_exit_code = exit_code) %>%
        unique()
    native_status <- read_csv(file.path(dir, "status_native.csv"), col_names = status_col_names, show_col_types = FALSE) %>%
        rename(native_exit_code = exit_code) %>%
        unique()
    miri_comp_status <- read_csv(file.path(dir, "status_miri_comp.csv"), col_names = status_col_names, show_col_types = FALSE) %>%
        rename(miri_comp_exit_code = exit_code) %>%
        unique()
    status <- native_comp_status %>%
        full_join(native_status, by = c("crate_name", "test_name")) %>%
        full_join(miri_comp_status, by = c("crate_name", "test_name"))
    errors <- bind_rows(stack_errors, tree_errors) %>%
        select(crate_name, test_name, borrow_mode, error_type, error_text, error_root, exit_code) %>%
        unique() %>%
        pivot_wider(names_from = borrow_mode, values_from = c(error_type, error_text, error_root, exit_code))
    status %>%
        full_join(errors, by = c("crate_name", "test_name")) %>%
        select(
            crate_name,
            test_name,
            native_comp_exit_code,
            native_exit_code,
            miri_comp_exit_code,
            exit_code_stack,
            exit_code_tree,
            error_type_stack,
            error_type_tree,
            error_text_stack,
            error_text_tree,
            error_root_stack,
            error_root_tree
        )
}

# errors can only be deduplicated if they have a root under both stack and tree borrows.
# otherwise, we cannot be sure that any two errors are the same, since a "NA" root could be anywhere
deduplicate_errors <- function(df) {
    deduplicable <- df %>%
        filter(!is.na(error_root_stack) & !is.na(error_root_tree))
    deduplicated <- deduplicable %>%
        group_by(across(c(-test_name))) %>%
        slice(1) %>%
        ungroup()
    not_deduplicable <- df %>%
        anti_join(deduplicable, by = c("crate_name", "test_name"))
    return(bind_rows(not_deduplicable, deduplicated))
}

baseline <- compile_errors("./data/results/stage3/baseline")
zeroed <- compile_errors("./data/results/stage3/zeroed")
uninit <- compile_errors("./data/results/stage3/uninit")
all_errors <- bind_rows(baseline, zeroed, uninit) %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors.csv"))


remove_erroneous_failures <- function(df, dir) {
    to_remove <- df %>%
        filter(errored_exit_code(native_exit_code) & errored_exit_code(exit_code_stack) & errored_exit_code(exit_code_tree)) %>%
        filter(str_detect(error_type_stack, "Test Failed")) %>%
        filter(str_detect(error_type_tree, "Test Failed"))
    df %>% anti_join(to_remove)
}

keep_actual_errors <- function(df) {
    df %>%
        filter(native_comp_exit_code == 0 & miri_comp_exit_code == 0) %>%
        select(-miri_comp_exit_code, -native_comp_exit_code) %>%
        filter(errored_exit_code(exit_code_stack) | errored_exit_code(exit_code_tree)) %>%
        deduplicate_errors() %>%
        filter(valid_error_type(error_type_stack) | valid_error_type(error_type_tree)) %>%
        remove_erroneous_failures()
}
shared_errors <- zeroed %>%
    inner_join(uninit) %>%
    inner_join(baseline) %>%
    keep_actual_errors() %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors_unique.csv"))

differed_in_baseline <- baseline %>%
    anti_join(zeroed) %>%
    anti_join(uninit) %>%
    keep_actual_errors() %>%
    unique() %>%
    filter(error_text_stack != "using uninitialized data, but this operation requires initialized memory") %>%
    filter(error_text_tree != "using uninitialized data, but this operation requires initialized memory") %>%
    write_csv(file.path(stage3_root, "diff_errors_baseline.csv"))

differed_in_zeroed <- zeroed %>%
    anti_join(uninit) %>%
    anti_join(baseline) %>%
    keep_actual_errors() %>%
    unique() %>%
    write_csv(file.path(stage3_root, "diff_errors_zeroed.csv"))

differed_in_uninit <- uninit %>%
    anti_join(zeroed) %>%
    anti_join(baseline) %>%
    keep_actual_errors() %>%
    unique() %>%
    write_csv(file.path(stage3_root, "diff_errors_uninit.csv"))
