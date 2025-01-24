options(warn = 2)
source("./scripts/stage3/base.r")
stage3_root <- file.path("./build/stage3/")

if (!dir.exists(stage3_root)) {
  dir.create(stage3_root)
}
dataset_dir <- Sys.getenv("DATASET", "dataset")
if (!dir.exists(dataset_dir)) {
    stop("Directory not found: ", dataset_dir)
}

stats_file <- file.path(stage3_root, "./stage3.stats.csv")

stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

deduplication <- data.frame(state = character(), count = numeric(), type = character(), stringsAsFactors = FALSE)

zeroed_meta <- compile_metadata(file.path(stage3_root, "zeroed"))
uninit_meta <- compile_metadata(file.path(stage3_root, "uninit"))

meta <- uninit_meta %>%
  bind_rows(zeroed_meta)

colnames(meta) <- c("crate_name", "test_name", "borrow_mode", "memory_mode", paste0("log_", colnames(meta)[-c(1, 2, 3, 4)]))

meta_count <- meta %>%
  filter(log_LLVMEngaged == 1) %>%
  pivot_longer(cols = starts_with("log_"), names_to = "log", names_prefix = "log_", values_to = "value") %>%
  filter(value == 1) %>%
  select(-borrow_mode, -memory_mode) %>%
  unique()

stats <- meta_count %>%
  select(-crate_name, -test_name, -value) %>%
  group_by(log) %>%
  summarize(n = n()) %>%
  mutate(log = paste0("meta_", str_to_lower(log))) %>%
  rename(key = log, value = n) %>%
  bind_rows(stats)

stats <- meta_count %>%
  select(-test_name) %>%
  unique() %>%
  group_by(log) %>%
  summarize(n = n()) %>%
  mutate(log = paste0("meta_crates_", str_to_lower(log))) %>%
  rename(key = log, value = n) %>%
  bind_rows(stats)

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

zeroed_meta %>%
  bind_rows(uninit_meta) %>%
  select(-test_name, -borrow_mode, -memory_mode) %>%
  filter(LLVMEngaged == 1) %>%
  # set each column to 1 if it appears anywhere in a group
  group_by(crate_name) %>%
  summarize_all(~ as.numeric(any(. == 1))) %>%
  pivot_longer(
    cols = -c(crate_name),
    names_to = "flag_name",
    values_to = "present"
  ) %>%
  group_by(flag_name) %>%
  summarize(n = sum(present)) %>%
  write_csv(file.path(stage3_root, "metadata.csv"))

zeroed_raw <- compile_errors("./build/stage3/zeroed", file.path(dataset_dir, "stage3/zeroed")) %>%
  inner_join(tests_engaged, by = c("crate_name", "test_name"))

uninit_raw <- compile_errors("./build/stage3/uninit", file.path(dataset_dir, "stage3/uninit")) %>%
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

uninit <- uninit_raw %>%
  merge_passes_and_timeouts() %>%
  select(-memory_mode)

zeroed <- zeroed_raw %>%
  merge_passes_and_timeouts() %>%
  select(-memory_mode)

failures <- all_errors %>%
  filter(!errored_exit_code(native_exit_code)) %>%
  filter(
    error_to_examine(error_type_stack, exit_signal_no_stack, assertion_failure_stack) 
    | error_to_examine(error_type_tree, exit_signal_no_tree, assertion_failure_tree)
  ) %>%
  mutate(borrow_mode = ifelse(error_type_stack == "Test Failed", "stack", "tree")) %>%
  select(crate_name, test_name, exit_signal_no_stack, memory_mode, borrow_mode) %>%
  unique() %>%
  pivot_wider(names_from = memory_mode, values_from = borrow_mode) %>%
  group_by(crate_name, test_name) %>%
  summarize(zeroed = paste(zeroed, collapse = ", "), uninit = paste(uninit, collapse = ", ")) %>%
  write_csv(file.path(stage3_root, "failures.csv"))

deduplication <- add_row(deduplication, state = "After", count = failures %>% nrow(), type = "Failures")

stats <- stats %>% add_row(key = "num_failures", value = failures %>% nrow())

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

stats %>% write_csv(stats_file)