options(warn = 2)
source("./scripts/stage3/base.r")
stage3_root <- file.path("./build/stage3/")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}
stats_file <- file.path(stage3_root, "./stage3.stats.csv")

stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

deduplication <- data.frame(state = character(), count = numeric(), type = character(), stringsAsFactors = FALSE)

zeroed_meta <- compile_metadata("./results/stage3/zeroed")
uninit_meta <- compile_metadata("./results/stage3/uninit")
num_tests_uninit <- uninit_meta %>%
    filter(LLVMEngaged == 1) %>%
    nrow()
uninit_meta %>%
    select(-crate_name, -test_name, -borrow_mode, -memory_mode) %>%
    filter(LLVMEngaged == 1) %>%
    pivot_longer(everything()) %>%
    filter(value == 1) %>%
    group_by(name) %>%
    summarize(n = n())

tests_engaged <- zeroed_meta %>%
    filter(LLVMEngaged == 1) %>%
    select(crate_name, test_name) %>%
    unique()

stats <- stats %>% add_row(key = "num_tests_engaged", value = tests_engaged %>% nrow())

num_crates_engaged <- zeroed_meta %>%
    filter(LLVMEngaged == 1) %>%
    select(crate_name) %>%
    unique() %>%
    nrow()

stats <- stats %>% add_row(key = "num_crates_engaged", value = num_crates_engaged)

did_not_engage_zeroed <- zeroed_meta %>%
    filter(LLVMEngaged == 0) %>%
    select(crate_name, test_name, borrow_mode) %>%
    group_by(crate_name, test_name) %>%
    summarize(num_modes = n()) %>%
    filter(num_modes == 2) %>%
    unique()

stats <- stats %>% add_row(key = "num_tests_not_engaged_both", value = did_not_engage_zeroed %>% nrow())

engaged_in_only_one_mode <- zeroed_meta %>%
    filter(LLVMEngaged == 0) %>%
    select(crate_name, test_name, borrow_mode) %>%
    group_by(crate_name, test_name) %>%
    summarize(num_modes = n()) %>%
    filter(num_modes == 1) %>%
    unique()

stats <- stats %>% add_row(key = "num_tests_not_engaged_one", value = engaged_in_only_one_mode %>% nrow())

engaged_constructor_zeroed <- zeroed_meta %>%
    filter(LLVMInvokedConstructor == 1) %>%
    select(crate_name, test_name) %>%
    unique()

summarize_metadata(zeroed_meta) %>%
    bind_rows(summarize_metadata(uninit_meta)) %>%
    write_csv(file.path(stage3_root, "metadata.csv"))

zeroed_raw <- compile_errors("./results/stage3/zeroed") %>%
    inner_join(tests_engaged, by = c("crate_name", "test_name"))

uninit_raw <- compile_errors("./results/stage3/uninit") %>%
    inner_join(tests_engaged, by = c("crate_name", "test_name"))

all_errors <- bind_rows(zeroed_raw, uninit_raw) %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors.csv"))

failures_raw <- all_errors %>%
    filter(error_type_stack == "Test Failed" | error_type_tree == "Test Failed") %>%
    select(crate_name, test_name) %>%
    unique()

deduplication <- add_row(deduplication, state = "Before", count = failures_raw %>% nrow(), type = "Failures")
stats <- stats %>% add_row(key = "num_failures_raw", value = failures_raw %>% nrow())

error_to_examine <- function(error_type, signal_no, assertion_failure) {
    error_type == "Test Failed" & ((is.na(signal_no) & assertion_failure) | signal_no != 9)
}
failures <- all_errors %>%
    filter(!errored_exit_code(native_exit_code)) %>%
    filter(error_to_examine(error_type_stack, exit_signal_no_stack, assertion_failure_stack) | error_to_examine(error_type_tree, exit_signal_no_tree, assertion_failure_tree)) %>%
    mutate(borrow_mode = ifelse(error_type_stack == "Test Failed", "stack", "tree")) %>%
    select(crate_name, test_name, exit_signal_no_stack, memory_mode, borrow_mode) %>%
    unique() %>%
    pivot_wider(names_from = memory_mode, values_from = borrow_mode) %>%
    group_by(crate_name, test_name) %>%
    summarize(zeroed = paste(zeroed, collapse = ", "), uninit = paste(uninit, collapse = ", ")) %>%
    write_csv(file.path(stage3_root, "failures.csv"))

deduplication <- add_row(deduplication, state = "After", count = failures %>% nrow(), type = "Failures")
stats <- stats %>% add_row(key = "num_failures", value = failures %>% nrow())

uninit <- uninit_raw %>%
    merge_passes_and_timeouts() %>%
    select(-memory_mode)
zeroed <- zeroed_raw %>%
    merge_passes_and_timeouts() %>%
    select(-memory_mode)

deduplicate_with_logging <- function(df, mode) {
    raw_errors <- df %>%
        keep_only_valid_errors() %>%
        unique()

    deduplication <<- add_row(deduplication, state = "Before", count = raw_errors %>% nrow(), type = mode)
    stats <<- stats %>% add_row(key = paste0("num_errors_", mode, "_raw"), value = raw_errors %>% nrow())
    errors <- raw_errors %>%
        deduplicate() %>%
        unique()
    stats <<- stats %>% add_row(key = paste0("num_errors_", mode), value = errors %>% nrow())
    deduplication <<- add_row(deduplication, state = "After", count = errors %>% nrow(), type = mode)
    errors
}

## Errors that occurred in both modes
shared <- zeroed %>%
    inner_join(uninit, by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    deduplicate_with_logging("shared") %>%
    write_csv(file.path(stage3_root, "errors_unique.csv"))

## Errors that occurred in the 'Zeroed' evaluation mode
differed_in_zeroed <- zeroed %>%
    anti_join(uninit, na_matches = c("na"), by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    deduplicate_with_logging("zeroed") %>%
    write_csv(file.path(stage3_root, "diff_errors_zeroed.csv"))

## Errors that occurred in the 'Uninitalized' evaluation mode
differed_in_uninit <- uninit %>%
    anti_join(zeroed, na_matches = c("na"), by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    deduplicate_with_logging("uninit") %>%
    write_csv(file.path(stage3_root, "diff_errors_uninit.csv"))

deduplication <- deduplication %>% pivot_wider(names_from = type, values_from = count)
deduplication$total <- rowSums(deduplication[, -1], na.rm = TRUE)
deduplication %>% write_csv(file.path(stage3_root, "deduplication.csv"))
