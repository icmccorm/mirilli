suppressWarnings(suppressMessages(suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(stringr)
})))

# if the directory 'build' exists, remove it
if (dir.exists("./build")) {
    unlink("./build", recursive = TRUE)
}
# create the directory 'build'
dir.create("./build")

failed <- FALSE

all_crates <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))

stage1_failed_download <- read_csv(file.path("./data/results/stage1/failed_download.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage1_visited <- read_csv(file.path("./data/results/stage1/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage1 <- all_crates %>%
    anti_join(stage1_visited, by = c("crate_name", "version")) %>%
    anti_join(stage1_failed_download, by = c("crate_name", "version"))
missed_stage1_count <- missed_stage1 %>% nrow()

if (missed_stage1_count > 1) {
    print(paste0("Missed crates in stage1: ", missed_stage1_count))
    failed <- TRUE
}

all_crates_stage2 <- read_csv(file.path("./data/compiled/stage1/stage2.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage2_failed_download <- read_csv(file.path("./data/results/stage2/failed_download.csv"), col_names = c("crate_name", "version"), show_col_types = FALSE)
stage2_visited <- read_csv(file.path("./data/results/stage2/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage2 <- all_crates_stage2 %>%
    anti_join(stage2_visited, by = c("crate_name", "version")) %>%
    anti_join(stage2_failed_download, by = c("crate_name", "version"))
missed_stage2_count <- missed_stage2 %>% nrow()
if (missed_stage2_count > 1) {
    print(paste0("Missed crates in stage2: ", missed_stage2_count))
    failed <- TRUE
}

all_tests_stage3 <- read_csv(file.path("./data/compiled/stage2/stage3.csv"), show_col_types = FALSE, col_names = c("test_name", "crate_name", "version"))
all_crates_stage3 <- all_tests_stage3 %>% select(crate_name, version)


stage3_baseline_visited <- read_csv(file.path("./data/results/stage3/baseline/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage3_zeroed_visited <- read_csv(file.path("./data/results/stage3/zeroed/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage3_visited <- bind_rows(stage3_baseline_visited, stage3_zeroed_visited)
missed_crates_stage3 <- all_crates_stage3 %>%
    anti_join(stage3_visited, by = c("crate_name", "version"))
missed_crates_stage3_count <- missed_crates_stage3 %>% nrow()
if (missed_crates_stage3_count > 1) {
    print(paste0("Missed crates in stage3: ", missed_crates_stage3_count))
    failed <- TRUE
}
native_comp_baseline <- read_csv(file.path("./data/results/stage3/baseline/status_native_comp.csv"), show_col_types = FALSE)
native_comp_zeroed <- read_csv(file.path("./data/results/stage3/zeroed/status_native_comp.csv"), show_col_types = FALSE, col_names = c("exit_code", "test_name", "crate_name"))

visited_tests <- bind_rows(native_comp_baseline, native_comp_zeroed)
erroneous_stage3 <- visited_tests %>% filter(exit_code != 0)

missed_tests_stage3 <- all_tests_stage3 %>%
    anti_join(visited_tests, by = c("crate_name", "test_name"))
missed_tests_stage3 %>% 
    select("test_name", "crate_name", "version") %>%
    write_csv(file.path("./build/missed_tests_stage3.csv"), col_names = FALSE)
missed_tests_stage3_count <- missed_tests_stage3 %>% nrow()
if (missed_tests_stage3_count > 1) {
    print(paste0("Missed tests in stage3: ", missed_tests_stage3_count))
    failed <- TRUE
}
status_native_comp_stage2 <- read_csv(file.path("./data/results/stage2/status_rustc_comp.csv"), col_names = c("crate_name", "version", "exit_code"), show_col_types = FALSE) %>% 
    filter(exit_code != 0)
erroneous_stage3_new <- erroneous_stage3 %>%
    anti_join(status_native_comp_stage2, by = c("crate_name")) %>% 
    select(exit_code, crate_name) %>%
    unique()
erroneous_stage2_count <- status_native_comp_stage2 %>% nrow()
erroneous_stage3_count <- erroneous_stage3_new %>% nrow()
print_fail_counts <- function(df) {
    num_timed_out <- df %>% filter(exit_code == 124) %>% nrow()
    num_failed <- df %>% filter(exit_code != 0) %>% filter(exit_code != 124) %>% nrow()
    return (paste("(Timed out:", num_timed_out, ", Failed:", num_failed, ")"))
}
if (erroneous_stage2_count > 1) {
    print(paste0("Native stage2: ", print_fail_counts(status_native_comp_stage2)))
    failed <- TRUE
}
if (erroneous_stage3_count > 1) {
    print(paste0("Native stage3: ", print_fail_counts(erroneous_stage3_new)))
    failed <- TRUE
}

get_activated <- function(dir) {
    activated_tree <- read_csv(file.path(dir, "tree_metadata.csv"), show_col_types = FALSE)
    activated_stack <- read_csv(file.path(dir, "stack_metadata.csv"), show_col_types = FALSE)
    return (bind_rows(activated_tree, activated_stack) %>% select(test_name, crate_name) %>% unique())
}

activated_baseline <- get_activated("./data/results/stage3/baseline")
activated_zeroed <- get_activated("./data/results/stage3/zeroed")