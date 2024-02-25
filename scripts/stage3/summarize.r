options(warn = 2)
source("./scripts/stage3/base.r")
stage3_root <- file.path("./build/stage3/")
if (!dir.exists(stage3_root)) {
    dir.create(stage3_root)
}

stats_file <- file.path(stage3_root, "./stats.csv")
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

zeroed_meta <- compile_metadata("./results/stage3/zeroed")
uninit_meta <- compile_metadata("./results/stage3/uninit")

num_tests_engaged <- zeroed_meta %>%
    filter(LLVMEngaged == 1) %>%
    select(test_name, crate_name) %>%
    unique() %>%
    nrow()
stats <- stats %>% add_row(key = "num_tests_engaged", value = num_tests_engaged)
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

zeroed_meta_summary <- summarize_metadata(zeroed_meta)
uninit_meta_summary <- summarize_metadata(uninit_meta)
zeroed_meta_summary %>%
    bind_rows(uninit_meta_summary) %>%
    write_csv(file.path(stage3_root, "metadata.csv"))

zeroed_raw <- compile_errors("./results/stage3/zeroed")

zeroed_failed <- zeroed_raw %>% right_join(did_not_engage_zeroed, by = c("crate_name", "test_name"))
zeroed_failed_fn <- zeroed_failed %>%
    filter(grepl("can't call foreign function `", error_text_stack)) %>%
    filter(grepl("can't call foreign function `", error_text_tree)) %>%
    mutate(
        error_text_stack = str_extract(error_text_stack, "`(.*)` on OS", group = 1),
        error_text_tree = str_extract(error_text_tree, "`(.*)` on OS", group = 1)
    ) %>%
    select(crate_name, test_name, error_text_stack, error_text_tree) %>%
    unique()
failed_function_names <- (zeroed_failed_fn %>% select(crate_name, test_name, error_text_stack) %>% rename(error_text = error_text_stack)) %>%
    bind_rows(zeroed_failed_fn %>% select(crate_name, test_name, error_text_tree) %>% rename(error_text = error_text_tree)) %>%
    unique()
stopifnot(failed_function_names %>% nrow() == zeroed_failed_fn %>% nrow())

function_count <- failed_function_names %>%
    group_by(error_text) %>%
    summarize(n = n()) %>%
    arrange(desc(n))

count_pipe <- function_count %>%
    filter(error_text == "pipe2") %>%
    select(n) %>%
    pull()
stats <- stats %>% add_row(key = "num_not_engaged_pipe", value = count_pipe)

count_socket <- function_count %>%
    filter(error_text == "socket") %>%
    select(n) %>%
    pull()
stats <- stats %>% add_row(key = "num_not_engaged_socket", value = count_socket)

count_each_blake <- function_count %>% filter(grepl("blake3", error_text))
count_blake <- sum(count_each_blake$n)
stats <- stats %>% add_row(key = "num_not_engaged_blake", value = count_blake)

count_each_std <- function_count %>% filter(str_detect(error_text, "^_ZNS"))
count_std <- sum(count_each_std$n)
stats <- stats %>% add_row(key = "num_not_engaged_std", value = count_std)

num_failed_engaged_constructor <- zeroed_failed %>%
    inner_join(engaged_constructor_zeroed, by = c("crate_name", "test_name")) %>%
    select(crate_name, test_name) %>%
    unique() %>%
    nrow()

uninit_raw <- compile_errors("./results/stage3/uninit")

all_errors <- bind_rows(zeroed_raw, uninit_raw) %>%
    unique() %>%
    write_csv(file.path(stage3_root, "errors.csv"))


uninit <- uninit_raw %>%
    merge_passes_and_timeouts() %>%
    select(-memory_mode)
zeroed <- zeroed_raw %>%
    merge_passes_and_timeouts() %>%
    select(-memory_mode)

shared_errors <- zeroed %>%
    inner_join(uninit, by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    keep_actual_errors() %>%
    unique()

shared_errors %>%
    keep_only_ub() %>%
    write_csv(file.path(stage3_root, "errors_unique.csv"))

shared_failures <- shared_errors %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Shared")

shared_overflows <- shared_errors %>%
    overflowed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Shared")

# we keep errors in the baseline that are either unique to it, or that differ from the zereod/uninit errors
# however, we discard differences when the baseline error was due to using uninitialized memory,
# but there's a different result in either the zeroed or uninit modes.
tested_in_zereod_or_uninit <- zeroed %>%
    select(crate_name, test_name) %>%
    bind_rows(uninit %>% select(crate_name, test_name)) %>%
    unique()

differed_in_zeroed <- zeroed %>%
    anti_join(uninit, na_matches = c("na"), by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    keep_actual_errors() %>%
    unique()

zeroed_failures <- differed_in_zeroed %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Zeroed")

zeroed_overflows <- differed_in_zeroed %>%
    overflowed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Zeroed")

zeroed_non_failures <- differed_in_zeroed %>%
    keep_only_ub() %>%
    write_csv(file.path(stage3_root, "diff_errors_zeroed.csv"))

differed_in_uninit <- uninit %>%
    anti_join(zeroed, na_matches = c("na"), by = names(zeroed)[names(zeroed) %in% names(uninit)]) %>%
    keep_actual_errors() %>%
    unique()

uninit_failures <- differed_in_uninit %>%
    failed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Uninit")

uninit_overflows <- differed_in_uninit %>%
    overflowed_in_either_mode() %>%
    unique() %>%
    mutate(mode = "Uninit")

uninit_non_failures <- differed_in_uninit %>%
    keep_only_ub() %>%
    write_csv(file.path(stage3_root, "diff_errors_uninit.csv"))

all_failures_to_investigate <- bind_rows(
    shared_failures,
    zeroed_failures,
    uninit_failures
) %>%
    deduplicate_label_write(file.path(stage3_root, "failures.csv"))

all_overflows_to_investigate <- bind_rows(
    shared_overflows,
    zeroed_overflows,
    uninit_overflows
) %>% deduplicate_label_write(file.path(stage3_root, "overflows.csv"))

stats <- stats %>% write.csv(stats_file, row.names = FALSE, quote = FALSE)

bugs <- read_csv(file.path("./results/bugs.csv"), show_col_types = FALSE) %>%
    select(crate_name, version, root_crate_name, root_crate_version, test_name, issue, pull_request, commit, bug_type_override, memory_mode) %>%
    left_join(all_errors, by = c("crate_name", "version", "test_name", "memory_mode")) %>%
    mutate(id = row_number()) %>%
    mutate(
        error_type_tree = ifelse(!is.na(bug_type_override), bug_type_override, error_type_tree)
    ) %>%
    mutate(error_type = ifelse(str_equal(error_type_tree, "Borrowing Violation"), "Tree Borrows Violation", error_type_tree)) %>%
    filter(!is.na(pull_request) | !is.na(commit) | !is.na(issue)) %>%
    select(
        id,
        crate_name,
        version,
        root_crate_name,
        root_crate_version,
        test_name,
        error_type,
        issue,
        pull_request,
        commit
    ) %>%
    write_csv(file.path(stage3_root, "bugs.csv"))
