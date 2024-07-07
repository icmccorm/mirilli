# if there's a command line argument equal to "-i", then set 'ignore_regression' to TRUE. Else, set it to FALSE
first_arg <- commandArgs(trailingOnly = TRUE)[1]
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
  num_timed_out <- df %>%
    filter(exit_code == 124) %>%
    nrow()
  num_failed <- df %>%
    filter(exit_code != 0) %>%
    filter(exit_code != 124) %>%
    nrow()
  return(paste0("(Timed out: ", num_timed_out, ", Failed: ", num_failed, ")"))
}


failed <- FALSE

all_crates <- read_csv(file.path("./results/population.csv"), show_col_types = FALSE) %>%
  select(crate_name, version)

exclude_crates <- read_csv(file.path("./results/exclude.csv"), show_col_types = FALSE)

# STAGE 1
print_stage(1)
stage1_failed_download <- read_csv(file.path("./results/stage1/failed_download.csv"), show_col_types = FALSE)
stage1_visited <- read_csv(file.path("./results/stage1/visited.csv"), show_col_types = FALSE)
missed_stage1 <- all_crates %>%
  anti_join(stage1_visited, by = c("crate_name", "version")) %>%
  anti_join(stage1_failed_download, by = c("crate_name", "version"))
missed_stage1_count <- missed_stage1 %>% nrow()

if (missed_stage1_count > 1) {
  message(paste0("x - There were ", missed_stage1_count, " missed crates in stage1."))
  failed <- TRUE
} else {
  message("✓ - All crates were visited in stage1")
}

# STAGE 2
print_stage(2)
all_crates_stage2 <- read_csv(file.path("./build/stage1/stage2.csv"), show_col_types = FALSE)
stage2_failed_download <- read_csv(file.path("./results/stage2/failed_download.csv"), show_col_types = FALSE)
stage2_visited <- read_csv(file.path("./results/stage2/visited.csv"), show_col_types = FALSE)
missed_stage2 <- all_crates_stage2 %>%
  anti_join(stage2_visited, by = c("crate_name", "version")) %>%
  anti_join(stage2_failed_download, by = c("crate_name", "version"))
missed_stage2_count <- missed_stage2 %>% nrow()
if (missed_stage2_count > 1) {
  message(paste0("x - There were ", missed_stage2_count, "missed crates in stage2."))
  failed <- TRUE
} else {
  message("✓ - All crates were visited in stage2")
}
status_native_comp_stage2 <- read_csv(file.path("./results/stage2/status_rustc_comp.csv"), show_col_types = FALSE) %>%
  filter(exit_code != 0)

erroneous_stage2_count <- status_native_comp_stage2 %>% nrow()

if (erroneous_stage2_count > 1) {
  if (!ignore_regression) {
    message(paste0("x - Certain crate(s) didn't compile ", message_fail_counts(status_native_comp_stage2)))
    failed <- TRUE
  }
} else {
  message(paste0("✓ - All crates continued to compile in stage2"))
}
status_miri_comp <- read_csv(file.path("./results/stage2/status_miri_comp.csv"), show_col_types = FALSE) %>%
  filter(exit_code != 0) %>%
  select(crate_name)

tests <- read_csv(file.path("./results/stage2/tests.csv"), show_col_types = FALSE) %>%
  filter(!is.na(test_name)) %>%
  select(crate_name)


# STAGE 3
print_stage(3)
intended_tests_stage3 <- read_csv(file.path("./build/stage2/stage3.csv"), show_col_types = FALSE) %>%
  select(crate_name, test_name) %>%
  unique()
get_visited_tests <- function(dir) {
  read_csv(file.path(dir, "status_native_comp.csv"), show_col_types = FALSE) %>%
    select(crate_name, test_name) %>%
    unique()
}

visited_tests_zeroed <- get_visited_tests("./results/stage3/zeroed/")
visited_tests_uninit <- get_visited_tests("./results/stage3/uninit/")
visited_tests_all <- bind_rows(visited_tests_zeroed, visited_tests_uninit) %>% unique()

missing_tests <- intended_tests_stage3 %>%
  anti_join(visited_tests_all, by = c("crate_name", "test_name")) %>%
  anti_join(exclude_crates, by = c("crate_name"))

missing_tests_count <- missing_tests %>% nrow()
if (missing_tests_count > 0) {
  message(paste0("x - There are ", missing_tests_count, " tests missing across all of stage3"))
  failed <- TRUE
} else {
  message("✓ - All tests were visited in stage3")
}

internal_validation_stage3 <- function(dir) {
  basename <- basename(dir)
  status_native_comp <- read_csv(file.path(dir, "status_native_comp.csv"), show_col_types = FALSE)
  if ((status_native_comp %>% filter(exit_code != 0) %>% nrow()) > 0) {
    if (!ignore_regression) {
      message(paste0("x - Certain test(s) failed to compile for ", basename, ":\t", message_fail_counts(status_native_comp)))
      failed <- TRUE
    }
  } else {
    message(paste0("✓ - All tests continued to compile in ", basename))
  }

  status_miri_comp <- read_csv(file.path(dir, "status_miri_comp.csv"), show_col_types = FALSE)

  erroneous_count <- status_miri_comp %>%
    filter(exit_code != 0) %>%
    select(test_name, crate_name) %>%
    write_csv(file.path("rerun.csv")) %>%
    nrow()
  if (erroneous_count > 0) {
    if (!ignore_regression) {
      message(paste0("x - Certain test(s) failed to compile in miri for ", basename, ":\t", message_fail_counts(status_miri_comp)))
      failed <- TRUE
    }
  }
}

internal_validation_stage3("./results/stage3/zeroed")
internal_validation_stage3("./results/stage3/uninit")

tests_missed_zeroed_uninit <- visited_tests_zeroed %>%
  anti_join(visited_tests_uninit, by = c("crate_name", "test_name")) %>%
  anti_join(exclude_crates, by = c("crate_name"))


read_activated <- function(path) {
  activated_tree <- read_csv(file.path(path, "metadata_tree.csv"), show_col_types = FALSE) %>%
    filter(LLVMEngaged == 1) %>%
    select(test_name, crate_name) %>%
    unique()
  activated_stack <- read_csv(file.path(path, "metadata_tree.csv"), show_col_types = FALSE) %>%
    filter(LLVMEngaged == 1) %>%
    select(test_name, crate_name) %>%
    unique()
  return(bind_rows(activated_tree, activated_stack) %>% unique())
}

activated_zeroed <- read_activated("./results/stage3/zeroed")
activated_uninit <- read_activated("./results/stage3/uninit")


if (activated_zeroed %>% anti_join(activated_uninit) %>% nrow() == 0) {
  message("✓ - Each evaluation method covered the same tests.")
} else {
  message("ERROR")
}
