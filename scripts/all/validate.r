# if there's a command line argument equal to "-i", then set 'ignore_regression' to TRUE. Else, set it to FALSE
first_arg = commandArgs(trailingOnly = TRUE)[1]
ignore_regression <- !is.na(first_arg) && first_arg == "-i"

suppressWarnings(suppressMessages(suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(stringr)
})))
print_stage <- function(num) {
    message("\n---------[Stage ", num, "]---------")
}
message_fail_counts <- function(df) {
    num_timed_out <- df %>% filter(exit_code == 124) %>% nrow()
    num_failed <- df %>% filter(exit_code != 0) %>% filter(exit_code != 124) %>% nrow()
    return (paste0("(Timed out: ", num_timed_out, ", Failed: ", num_failed, ")"))
}

logging_dir <- file.path("./validation")
# if the directory 'build' exists, remove it
if (dir.exists(logging_dir)) {
    unlink(logging_dir, recursive = TRUE)
}
# create the directory 'build'
dir.create(logging_dir)
failed <- FALSE

all_crates <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
exclude_crates <- read_csv(file.path("./data/results/exclude.csv"), show_col_types = FALSE, col_names = c("crate_name"))

# STAGE 1
print_stage(1)
stage1_failed_download <- read_csv(file.path("./data/results/stage1/failed_download.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage1_visited <- read_csv(file.path("./data/results/stage1/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage1 <- all_crates %>%
    anti_join(stage1_visited, by = c("crate_name", "version")) %>%
    anti_join(stage1_failed_download, by = c("crate_name", "version"))
missed_stage1_count <- missed_stage1 %>% nrow()

if (missed_stage1_count > 1) {
    message(paste0("x - There were ", missed_stage1_count, "missed crates in stage1."))
    failed <- TRUE
}else{
    message("✓ - All crates were visited in stage1")
}

# STAGE 2
print_stage(2)
all_crates_stage2 <- read_csv(file.path("./data/compiled/stage1/stage2.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage2_failed_download <- read_csv(file.path("./data/results/stage2/failed_download.csv"), col_names = c("crate_name", "version"), show_col_types = FALSE)
stage2_visited <- read_csv(file.path("./data/results/stage2/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage2 <- all_crates_stage2 %>%
    anti_join(stage2_visited, by = c("crate_name", "version")) %>%
    anti_join(stage2_failed_download, by = c("crate_name", "version"))
missed_stage2_count <- missed_stage2 %>% nrow()
if (missed_stage2_count > 1) {
    message(paste0("x - There were ", missed_stage2_count, "missed crates in stage2."))
    failed <- TRUE
}else{
    message("✓ - All crates were visited in stage2")
}
status_native_comp_stage2 <- read_csv(file.path("./data/results/stage2/status_rustc_comp.csv"), col_names = c("crate_name", "version", "exit_code"), show_col_types = FALSE) %>% 
    filter(exit_code != 0)

erroneous_stage2_count <- status_native_comp_stage2 %>% nrow()

if (erroneous_stage2_count > 1) {
    if (!ignore_regression){
        message(paste0("x - Certain crate(s) didn't compile ", message_fail_counts(status_native_comp_stage2)))
        failed <- TRUE
    }
    print(status_native_comp_stage2)
}else{
    message(paste0("✓ - All crates continued to compile in stage2"))
}
# STAGE 3
print_stage(3)
intended_tests_stage3 <- read_csv(file.path("./data/compiled/stage2/stage3.csv"), show_col_types = FALSE, col_names = c("test_name", "crate_name", "version")) %>% select(crate_name, test_name) %>% unique()
get_visited_tests <- function(dir) {
    read_csv(file.path(dir, "status_native_comp.csv"), show_col_types = FALSE, col_names=c("exit_code", "crate_name", "test_name")) %>% select(crate_name, test_name) %>% unique()
}
visited_tests_baseline <- get_visited_tests("./data/results/stage3/baseline/")
visited_tests_zeroed <- get_visited_tests("./data/results/stage3/zeroed/")
visited_tests_uninit <- get_visited_tests("./data/results/stage3/uninit/")
visited_tests_all <- bind_rows(visited_tests_baseline, visited_tests_zeroed, visited_tests_uninit) %>% unique()
missing_tests <- intended_tests_stage3 %>%
    anti_join(visited_tests_all, by = c("crate_name", "test_name")) %>% 
    anti_join(exclude_crates, by = c("crate_name"))
missing_tests_count <- missing_tests %>% nrow()
if (missing_tests_count > 0) {
    message(paste0("x - There are ", missing_tests_count, " tests missing across all of stage3"))
    failed <- TRUE
}else{
    message("✓ - All tests were visited in stage3")
}

internal_validation_stage3 <- function(dir) {
    basename <- basename(dir)
    status_native_comp <- read_csv(file.path(dir, "status_native_comp.csv"), show_col_types = FALSE, col_names = c("exit_code", "crate_name", "test_name"))
    erroneous_count <- status_native_comp %>% filter(exit_code != 0) %>% nrow()
    if (erroneous_count > 0) {
        if (!ignore_regression) {
            message(paste0("x - Certain test(s) failed to compile for ", basename, ":\t", message_fail_counts(status_native_comp)))
            failed <- TRUE
        }
    }else{
        message(paste0("✓ - All tests continued to compile in ", basename))
    }
}

internal_validation_stage3("./data/results/stage3/baseline")
internal_validation_stage3("./data/results/stage3/zeroed")
internal_validation_stage3("./data/results/stage3/uninit")

tests_missed_zeroed_uninit <- visited_tests_zeroed %>%
    anti_join(visited_tests_uninit, by = c("crate_name", "test_name")) %>%
    anti_join(exclude_crates, by = c("crate_name"))
tests_missed_zeroed_count <- tests_missed_zeroed_uninit %>% nrow()
tests_missed_uninit_zeroed <- visited_tests_uninit %>%
    anti_join(visited_tests_zeroed, by = c("crate_name", "test_name")) %>%
    anti_join(exclude_crates, by = c("crate_name"))
tests_missed_uninit_count <- tests_missed_uninit_zeroed %>% nrow()

passed <- tests_missed_zeroed_count == 0 && tests_missed_uninit_count == 0
if (passed) {
    message("✓ - Each evaluation method covered the same tests.")
} else {
    if (tests_missed_zeroed_count > 0) {
        message(paste0("x - There are ", tests_missed_zeroed_uninit %>% nrow(), " tests from zeroed that still need to be run for uninit."))
        failed <- TRUE
    }
    if (tests_missed_uninit_count > 0) {
        message(paste0("x - There are ", tests_missed_uninit_zeroed %>% nrow(), " tests from uninit that still need to be run for zeroed."))
        failed <- TRUE
    }
}

visited_tests_in_evaluation <- bind_rows(visited_tests_zeroed, visited_tests_uninit) %>% unique()
activated_tests_in_initial_run <- read_csv(file.path("./data/results/stage3/baseline/activated.csv"), show_col_types = FALSE, col_names = c("crate_name", "test_name")) %>% unique()

visited_activated_tests <- activated_tests_in_initial_run %>% anti_join(activated_tests_in_initial_run, by = c("crate_name", "test_name"))
tests_activated_in_initial_run_count <- visited_activated_tests %>% nrow()
if (tests_activated_in_initial_run_count > 0) {
    message(paste0("x - There are ", tests_activated_in_initial_run_count, " tests that were activated in the initial run but not in the evaluation."))
    failed <- TRUE
}else{
    message("✓ - All tests activated in the initial run were also activated in the evaluation.")
}