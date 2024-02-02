suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(stringr)
    library(tidyr)
})
options(dplyr.summarise.inform = FALSE)

stage3_root <- file.path("./build/stage3/")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}

STACK_OVERFLOW_TXT <- "Stack Overflow"
UNSUPP_ERR_TXT <- "Unsupported Operation"
LLI_ERR_TXT <- "LLI Internal Error"
TIMEOUT_ERR_TXT <- "Timeout"
TIMEOUT_PASS_ERR_TXT <- "Passed/Timeout"
TEST_FAILED_TXT <- "Test Failed"
TERMINATED_EARLY_ERR_TXT <- "Main Terminated Early"
USING_UNINIT_FULL_ERR_TXT <- "using uninitialized data, but this operation requires initialized memory"
INTEROP_ERR_TXT <- "LLI Interoperation Error"
UB_MAYBEUNINIT <- "Invalid MaybeUninit<T>"
UB_MEM_UNINIT <- "Invalid mem::uninitialized()"
PASS_ERR_TEXT <- "Passed"

UNWIND_ERR_TEXT <- "unwinding past the topmost frame of the stack"
UNWIND_ERR_TYPE <- "Unwinding Past Topmost Frame"

CROSS_LANGUAGE_ERR_TEXT <- "which is [C|Rust] heap memory, using [C|Rust] heap deallocation operation"
CROSS_LANGUAGE_ERR_TYPE <- "Cross Language Deallocation"

INVALID_VALUE_UNINIT_ERR_TYPE <- "Invalid Uninitialized Value"
INVALID_VALUE_UNINIT_ERR_TEXT <- "encountered uninitialized memory, but expected"

INVALID_VALUE_UNALIGNED_ERR_TYPE <- "Unaligned Reference"
INVALID_VALUE_UNALIGNED_ERR_TEXT <- "invalid value: encountered an unaligned reference"

INVALID_ENUM_TAG_ERR_TEXT <- "but expected a valid enum tag"
INVALID_VALUE_ENUM_TAG_ERR_TYPE <- "Invalid Enum Tag"

can_deduplicate_without_error_root <- function(error_type) {
    return(error_type %in% c(LLI_ERR_TXT, UNSUPP_ERR_TXT, TIMEOUT_ERR_TXT, TIMEOUT_PASS_ERR_TXT, TERMINATED_EARLY_ERR_TXT))
}

deduplicate_error_text <- function(df) {
    df <- df %>%
        mutate(error_text = str_replace(error_text, "alloc[0-9]+", "alloc")) %>%
        mutate(error_text = str_replace(error_text, "<[0-9]+>", "<>")) %>%
        mutate(error_text = str_replace(error_text, "call [0-9]+", "call <>")) %>%
        mutate(error_text = str_replace(error_text, paste0("^", error_type, ":"), "")) %>%
        mutate(error_text = str_replace(error_text, "0x[0-9a-f]+\\[noalloc\\]", "[noalloc]")) %>%
        mutate(error_text = trimws(error_text))
    return(df)
}

correct_error_type <- function(df) {
    df <- df %>%
        mutate(error_type = if_else(str_detect(error_text, UNWIND_ERR_TEXT), UNWIND_ERR_TYPE, error_type)) %>%
        mutate(error_type = if_else(str_detect(error_text, CROSS_LANGUAGE_ERR_TEXT), CROSS_LANGUAGE_ERR_TYPE, error_type)) %>%
        mutate(error_type = if_else(str_detect(error_text, INVALID_VALUE_UNALIGNED_ERR_TEXT), INVALID_VALUE_UNALIGNED_ERR_TYPE, error_type)) %>%
        mutate(error_type = if_else(str_detect(error_text, INVALID_ENUM_TAG_ERR_TEXT), INVALID_VALUE_ENUM_TAG_ERR_TYPE, error_type)) %>%
        mutate(error_type = if_else(str_detect(error_text, INVALID_VALUE_UNINIT_ERR_TEXT), INVALID_VALUE_UNINIT_ERR_TYPE, error_type)) %>%
        mutate(error_type = if_else(str_detect(error_type, "deadlock"), "Deadlock", error_type))
}


valid_error_type <- function(type, trace) {
    !(type %in% c(
        UNSUPP_ERR_TXT,
        LLI_ERR_TXT,
        TIMEOUT_ERR_TXT,
        TIMEOUT_PASS_ERR_TXT,
        UB_MAYBEUNINIT,
        UB_MEM_UNINIT
    )) | (type %in% c(UB_MAYBEUNINIT, UB_MEM_UNINIT) & str_starts(trace, "/root/.cargo/registry/src/index.crates.io"))
}
passed <- function(exit_code) {
    exit_code == 0
}
timed_out <- function(exit_code) {
    exit_code == 124
}
errored_exit_code <- function(exit_code) {
    !passed(exit_code) & !timed_out(exit_code)
}

failed_in_either_mode <- function(df) {
    df %>% filter(
        error_type_stack == TEST_FAILED_TXT & is.na(exit_signal_no_stack) |
            error_type_tree == TEST_FAILED_TXT & is.na(exit_signal_no_stack)
    )
}

overflowed_in_either_mode <- function(df) {
    df %>% filter(
        error_type_stack == STACK_OVERFLOW_TXT |
            error_type_tree == STACK_OVERFLOW_TXT
    )
}

error_in_dependency <- function(error_root) {
    str_detect(error_root, "/root/.cargo/registry/src/index.crates.io-")
}

possible_non_failure_bug <- function(error_type, trace) {
    valid_error_type(error_type, trace) & error_type != TEST_FAILED_TXT & error_type != STACK_OVERFLOW_TXT
}

keep_only_ub <- function(df) {
    df %>% filter(possible_non_failure_bug(error_type_stack, error_root_stack) | possible_non_failure_bug(error_type_tree, error_root_tree))
}

prepare_errors <- function(dir, type) {
    error_path <- file.path(dir, paste0("error_info_", type, ".csv"))
    root_path <- file.path(dir, paste0("error_roots_", type, ".csv"))

    errors <- read_csv(error_path, show_col_types = FALSE) %>%
        inner_join(all, by = c("crate_name"))
    error_roots <- read_csv(root_path, show_col_types = FALSE)

    error_rust_locations <- errors %>%
        select(crate_name, test_name, error_location_rust)

    error_roots <- error_roots %>%
        full_join(error_rust_locations, by = c("crate_name", "test_name")) %>%
        mutate(error_root = if_else(is.na(error_root), error_location_rust, error_root)) %>%
        select(-error_location_rust)

    errors <- errors %>%
        full_join(error_roots, by = c("crate_name", "test_name")) %>%
        correct_error_type() %>%
        deduplicate_error_text()

    exit_codes <- read_csv(file.path(dir, paste0("status_", type, ".csv")), col_names = c("exit_code", "crate_name", "test_name"), show_col_types = FALSE)

    errors <- errors %>%
        full_join(exit_codes, by = c("crate_name", "test_name")) %>%
        mutate(error_type = if_else(timed_out(exit_code), TIMEOUT_ERR_TXT, error_type)) %>%
        mutate(borrow_mode = type)
    borrow_summary <- read_csv(file.path(dir, paste0(type, "_summary.csv")), show_col_types = FALSE)
    errors <- errors %>% full_join(borrow_summary, by = c("crate_name", "test_name"))
    return(errors)
}

all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))

compile_errors <- function(dir) {
    basename <- basename(dir)

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
        select(crate_name, test_name, borrow_mode, error_type, error_text, error_root, exit_code, actual_failure, exit_signal_no, action, kind) %>%
        unique() %>%
        pivot_wider(names_from = borrow_mode, values_from = c(error_type, error_text, error_root, exit_code, actual_failure, exit_signal_no, action, kind))

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
            error_text_stack,
            error_text_tree,
            error_root_stack,
            error_root_tree,
            action_stack,
            action_tree,
            kind_stack,
            kind_tree,
            actual_failure_stack,
            actual_failure_tree,
            exit_signal_no_stack,
            exit_signal_no_tree
        ) %>%
        mutate(memory_mode = basename)
}

merge_passes_and_timeouts <- function(df) {
    df <- mutate(
        df,
        exit_code_stack = if_else(timed_out(exit_code_stack) & error_type_stack == TIMEOUT_ERR_TXT, 0, exit_code_stack),
        exit_code_tree = if_else(timed_out(exit_code_tree) & error_type_tree == TIMEOUT_ERR_TXT, 0, exit_code_tree),
        error_type_stack = if_else(passed(exit_code_stack), TIMEOUT_PASS_ERR_TXT, error_type_stack),
        error_type_tree = if_else(passed(exit_code_tree), TIMEOUT_PASS_ERR_TXT, error_type_tree)
    )
}

deduplicate_errors <- function(df) {
    # we can only deduplicate errors that are not test failures, and that have a non-NA error root
    can_deduplicate <- df %>%
        filter(is.na(error_type_stack) | error_type_stack != TEST_FAILED_TXT) %>%
        filter(is.na(error_type_tree) | error_type_tree != TEST_FAILED_TXT) %>%
        filter(ifelse(errored_exit_code(exit_code_stack), !is.na(error_root_stack) | can_deduplicate_without_error_root(error_type_stack), TRUE)) %>%
        filter(ifelse(errored_exit_code(exit_code_tree), !is.na(error_root_tree) | can_deduplicate_without_error_root(error_type_tree), TRUE))
    # we want to deduplicate across everything except the name of a test.
    deduplicated <- can_deduplicate %>%
        group_by(across(c(-test_name))) %>%
        mutate(num_duplicates = n()) %>%
        slice(1) %>%
        ungroup()

    error_in_deps <- deduplicated %>%
        filter((error_in_dependency(error_root_stack) & error_in_dependency(error_root_tree)) |
            (is.na(error_root_stack) & error_in_dependency(error_root_tree)) |
            (is.na(error_root_tree) & error_in_dependency(error_root_stack)))

    deduplicated <- deduplicated %>%
        anti_join(error_in_deps, by = names(deduplicated)[names(deduplicated) %in% names(error_in_deps)])

    error_in_deps <- error_in_deps %>%
        group_by(across(c(-test_name, -crate_name, -version))) %>%
        mutate(num_duplicates = n()) %>%
        slice(1) %>%
        ungroup()

    not_deduplicable <- df %>%
        anti_join(can_deduplicate, by = names(df)[names(can_deduplicate) %in% names(df)]) %>%
        mutate(num_duplicates = 1)

    return(bind_rows(not_deduplicable, deduplicated, error_in_deps))
}

remove_erroneous_failures <- function(df, dir) {
    to_remove <- df %>%
        filter(errored_exit_code(native_exit_code) & errored_exit_code(exit_code_stack) & errored_exit_code(exit_code_tree)) %>%
        filter(str_detect(error_type_stack, TEST_FAILED_TXT)) %>%
        filter(str_detect(error_type_tree, TEST_FAILED_TXT))
    df %>% anti_join(to_remove, by = names(df)[names(to_remove) %in% names(df)])
}

keep_actual_errors <- function(df) {
    df %>%
        # we only want to include cases where a test passed both native compilation and miri
        filter(passed(native_comp_exit_code) & passed(miri_comp_exit_code)) %>%
        select(-miri_comp_exit_code, -native_comp_exit_code) %>%
        # then, we require that the test errored in either stacked borrows or tree borrows
        filter(errored_exit_code(exit_code_stack) | errored_exit_code(exit_code_tree)) %>%
        # finally, there must be a valid error type in either category
        filter(valid_error_type(error_type_stack, error_root_stack) | valid_error_type(error_type_tree, error_root_tree)) %>%
        deduplicate_errors() %>%
        remove_erroneous_failures()
}

compile_metadata <- function(dir) {
    stack_meta <- read_csv(file.path(dir, "metadata_stack.csv"), show_col_types = FALSE) %>% mutate(borrow_mode = "stack")
    tree_meta <- read_csv(file.path(dir, "metadata_tree.csv"), show_col_types = FALSE) %>% mutate(borrow_mode = "tree")
    return(bind_rows(stack_meta, tree_meta) %>%
        mutate(memory_mode = basename(dir)))
}
summarize_metadata <- function(df) {
    # pivot longer such that borrow_mode and memory_mode are still columns, but the rest are rows
    # get all column names except for borrow_mode and memory_mode
    counts_under_configuration <- df %>%
        select(test_name, crate_name) %>%
        unique() %>%
        nrow()
    by_config <- df %>%
        pivot_longer(
            cols = colnames(df)
            %>% setdiff(c("crate_name", "test_name", "borrow_mode", "memory_mode"))
        ) %>%
        select(-crate_name, -test_name)
    by_config %>%
        group_by(borrow_mode, memory_mode, name) %>%
        summarize(count = n(), percent = round(n() / counts_under_configuration, 1)) %>%
        ungroup()
}

deduplicate_label_write <- function(df, path) {
    df %>%
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
        write_csv(path)
}
