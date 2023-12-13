library(dplyr)
library(readr)
library(stringr)
library(tidyr)
stage3_root <- file.path("./data/compiled/stage3/")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}

UNSUPP_ERR_TXT <- "Unsupported Operation"
LLI_ERR_TXT <- "LLI Internal Error"
TIMEOUT_ERR_TXT <- "Timeout"
TIMEOUT_PASS_ERR_TXT <- "Passed/Timeouts"
TEST_FAILED_TXT <- "Test Failed"
TEMINATED_EARLY_FULL_ERR_TXT <- "the main thread terminated without waiting for all remaining threads"
TERMINATED_EARLY_ERR_TXT <- "Main Terminated Early"
USING_UNINIT_FULL_ERR_TXT <- "using uninitialized data, but this operation requires initialized memory"
MEMORY_LEAKED_ERR_TXT <- "Memory Leaked"
UB_ERR_TXT <- "Undefined Behavior"
INTEROP_ERR_TXT <- "LLI Interoperation Error"

deduplicate_error_text <- function(df) {
    df <- df %>%
        mutate(full_error_text = str_replace(full_error_text, "alloc[0-9]+", "alloc")) %>%
        mutate(full_error_text = str_replace(full_error_text, "<[0-9]+>", "<>")) %>%
        mutate(full_error_text = str_replace(full_error_text, "call [0-9]+", "call <>")) %>%
        mutate(full_error_text = str_replace(full_error_text, paste0("^", error_type, ":"), "")) %>%
        mutate(full_error_text = trimws(full_error_text))
    return(df)
}
valid_error_type <- function(type) {
    (type != UNSUPP_ERR_TXT & type != LLI_ERR_TXT & type != TIMEOUT_ERR_TXT & type != TIMEOUT_PASS_ERR_TXT)
}
errored_exit_code <- function(exit_code) {
    exit_code != 0 & exit_code != 124
}
failed_in_either_mode <- function(df) {
    df %>% filter(
        error_type_stack == TEST_FAILED_TXT |
            error_type_tree == TEST_FAILED_TXT
    )
}
fix_error_type_text <- function(df) {
    df %>%
        mutate(error_type = str_replace(
            error_type,
            str_to_lower(MEMORY_LEAKED_ERR_TXT),
            MEMORY_LEAKED_ERR_TXT
        )) %>%
        mutate(error_type = str_replace(
            error_type,
            TEMINATED_EARLY_FULL_ERR_TXT,
            TERMINATED_EARLY_ERR_TXT
        ))
}

possible_non_failure_bug <- function(error_type) {
    error_type %in% c(INTEROP_ERR_TXT, UB_ERR_TXT, MEMORY_LEAKED_ERR_TXT, TERMINATED_EARLY_ERR_TXT)
}

keep_only_non_failures <- function(df) {
    failures <- df %>%
        filter(error_type_stack == TEST_FAILED_TXT | error_type_tree == TEST_FAILED_TXT) %>%
        filter(!possible_non_failure_bug(error_type_stack) | !possible_non_failure_bug(error_type_tree))
    df %>% anti_join(failures)
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
        mutate(borrow_mode = type) %>%
        fix_error_type_text()
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
    errors <- bind_rows(stack_errors, tree_errors)
    errors <- errors %>%
        select(crate_name, test_name, borrow_mode, error_type, full_error_text, error_root, exit_code, actual_failure, exit_signal_no) %>%
        unique() %>%
        pivot_wider(names_from = borrow_mode, values_from = c(error_type, full_error_text, error_root, exit_code, actual_failure, exit_signal_no))
    status %>%
        full_join(errors, by = c("crate_name", "test_name")) %>%
        inner_join(all, by = c("crate_name")) %>%
        select(
            crate_name,
            version,
            test_name,
            native_comp_exit_code,
            native_exit_code,
            miri_comp_exit_code,
            exit_code_stack,
            exit_code_tree,
            error_type_stack,
            error_type_tree,
            full_error_text_stack,
            full_error_text_tree,
            error_root_stack,
            error_root_tree,
            actual_failure_stack,
            actual_failure_tree,
            exit_signal_no_stack,
            exit_signal_no_tree
        )
}

deduplicate_errors <- function(df) {
    df <- mutate(
        df,
        exit_code_stack = if_else(exit_code_stack == 124 & error_type_stack == TIMEOUT_ERR_TXT, 0, exit_code_stack),
        exit_code_tree = if_else(exit_code_tree == 124 & error_type_tree == TIMEOUT_ERR_TXT, 0, exit_code_tree),
        error_type_stack = if_else(exit_code_stack == 0, "Passed/Timeout", error_type_stack),
        error_type_tree = if_else(exit_code_tree == 0, "Passed/Timeout", error_type_tree)
    )
    can_deduplicate <- df %>%
        filter(is.na(error_type_stack) | error_type_stack != TEST_FAILED_TXT) %>%
        filter(is.na(error_type_tree) | error_type_tree != TEST_FAILED_TXT) %>%
        filter(!(is.na(error_root_stack) & errored_exit_code(exit_code_stack))) %>%
        filter(!(is.na(error_root_tree) & errored_exit_code(exit_code_tree)))
    deduplicated <- can_deduplicate %>%
        group_by(across(c(-test_name))) %>%
        mutate(num_duplicates = n()) %>%
        slice(1) %>%
        ungroup()
    not_deduplicable <- df %>%
        anti_join(can_deduplicate) %>%
        mutate(num_duplicates = 1)
    return(bind_rows(not_deduplicable, deduplicated))
}

baseline <- compile_errors("./data/results/stage3/baseline")
zeroed <- compile_errors("./data/results/stage3/zeroed")
uninit <- compile_errors("./data/results/stage3/uninit")
problems(uninit)

all_errors <- bind_rows(baseline, zeroed, uninit) %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors.csv"))


remove_erroneous_failures <- function(df, dir) {
    to_remove <- df %>%
        filter(errored_exit_code(native_exit_code) & errored_exit_code(exit_code_stack) & errored_exit_code(exit_code_tree)) %>%
        filter(str_detect(error_type_stack, TEST_FAILED_TXT)) %>%
        filter(str_detect(error_type_tree, TEST_FAILED_TXT))
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
    keep_actual_errors() %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors_unique.csv"))

shared_failures <- shared_errors %>%
    filter(error_type_stack == TEST_FAILED_TXT | error_type_tree == TEST_FAILED_TXT) %>%
    unique() %>%
    mutate(mode = "Shared")


# we keep errors in the baseline that are either unique to it, or that differ from the zereod/uninit errors
# however, we discard differences when the baseline error was due to using uninitialized memory,
# but there's a different result in either the zeroed or uninit modes.
tested_in_zereod_or_uninit <- zeroed %>%
    select(crate_name, test_name) %>%
    bind_rows(uninit %>% select(crate_name, test_name)) %>%
    unique()
baseline_also <- baseline %>%
    filter(crate_name %in% tested_in_zereod_or_uninit$crate_name & test_name %in% tested_in_zereod_or_uninit$test_name)
baseline_unique <- baseline %>%
    anti_join(baseline_also, by = c("crate_name", "test_name")) %>%
    mutate(shared = FALSE)
baseline_also <- baseline_also %>%
    filter(full_error_text_stack != USING_UNINIT_FULL_ERR_TXT) %>%
    filter(full_error_text_tree != USING_UNINIT_FULL_ERR_TXT) %>%
    mutate(shared = TRUE)
baseline <- bind_rows(baseline_also, baseline_unique)

differed_in_baseline <- baseline %>%
    anti_join(zeroed) %>%
    anti_join(uninit) %>%
    keep_actual_errors() %>%
    select(-error_root_stack, -error_root_tree) %>%
    unique()

baseline_failures <- differed_in_baseline %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Baseline")

baseline_non_failures <- differed_in_baseline %>%
    keep_only_non_failures() %>%
    write_csv(file.path(stage3_root, "diff_errors_baseline.csv"))

differed_in_zeroed <- zeroed %>%
    anti_join(uninit) %>%
    keep_actual_errors() %>%
    unique()

zeroed_failures <- differed_in_zeroed %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Zeroed")

zeroed_non_failures <- differed_in_zeroed %>%
    keep_only_non_failures() %>%
    write_csv(file.path(stage3_root, "diff_errors_zeroed.csv"))

differed_in_uninit <- uninit %>%
    anti_join(zeroed) %>%
    keep_actual_errors() %>%
    unique()

uninit_failures <- differed_in_uninit %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Uninit")

uninit_non_failures <- differed_in_uninit %>%
    keep_only_non_failures() %>%
    write_csv(file.path(stage3_root, "diff_errors_uninit.csv"))

all_failures_to_investigate <- bind_rows(
    shared_failures,
    baseline_failures,
    zeroed_failures,
    uninit_failures
) %>%
    unique() %>%
    select(
        mode,
        crate_name,
        version,
        test_name,
        error_type_stack,
        error_type_tree,
        exit_code_stack,
        exit_code_tree,
        actual_failure_stack,
        actual_failure_tree,
        exit_signal_no_stack,
        exit_signal_no_tree,
        -shared
    ) %>%
    mutate(
        errored_in = ifelse(errored_exit_code(exit_code_tree),
            ifelse(errored_exit_code(exit_code_stack), "Both", "Tree"),
            ifelse(errored_exit_code(exit_code_stack), "Stack", NA)
        ),
        actual_failure = ifelse(errored_in == "Tree",
            actual_failure_tree,
            actual_failure_stack
        ),
        exit_signal_no = ifelse(errored_in == "Tree",
            exit_signal_no_tree,
            exit_signal_no_stack
        )
    ) %>%
    select(
        mode,
        crate_name,
        version,
        test_name,
        errored_in,
        error_type_stack,
        error_type_tree,
        actual_failure,
        exit_signal_no
    ) %>%
    write_csv(file.path(stage3_root, "failures.csv"))
