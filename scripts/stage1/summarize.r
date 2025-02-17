suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
})
options(dplyr.summarise.inform = FALSE)
dataset_dir <- Sys.getenv("DATASET", "dataset")
dataset_dir <- ifelse(dataset_dir == "", "dataset", dataset_dir)
if (!dir.exists(dataset_dir)) {
    stop("Directory not found: ", dataset_dir)
}
stage1_input_dir <- file.path(dataset_dir, "stage1")
stage1_output_dir <- file.path("./build/stage1")
if (!dir.exists(stage1_output_dir)) {
    dir.create(stage1_output_dir)
}
stats_file <- file.path(stage1_output_dir, "./stage1.stats.csv")
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

comp_status <- read_csv(file.path(stage1_input_dir, "status_comp.csv"), show_col_types = FALSE)

lint_status <- read_csv(file.path(stage1_input_dir, "status_lint.csv"), show_col_types = FALSE)

num_comp_all <- comp_status %>% nrow()
stats <- stats %>% add_row(key = "num_crates_all", value = num_comp_all)

num_comp_passed <- comp_status %>%
    filter(exit_code == 0) %>%
    nrow()
stats <- stats %>% add_row(key = "num_crates_compiled", value = num_comp_passed)

num_lint_all <- lint_status %>% nrow()
num_lint_passed <- lint_status %>%
    filter(exit_code == 0) %>%
    nrow()

test_counts <- read_csv(file.path(stage1_output_dir, "has_tests.csv"), show_col_types = FALSE)
num_had_tests <- test_counts %>%
    filter(test_count > 0) %>%
    select(crate_name) %>%
    unique() %>%
    nrow()
stats <- stats %>% add_row(key = "num_crates_had_tests", value = num_had_tests)


has_bytecode <- read_csv(file.path(stage1_input_dir, "has_bytecode.csv"), show_col_types = FALSE) %>% arrange(crate_name)
num_had_bytecode <- has_bytecode %>%
    select(crate_name) %>%
    unique() %>%
    nrow()
stats <- stats %>% add_row(key = "num_crates_had_bytecode", value = num_had_bytecode)

passed <- comp_status %>%
    filter(exit_code %in% c(0, 2)) %>%
    select(crate_name, version) %>%
    arrange(crate_name)

has_tests_and_bytecode <- has_bytecode %>%
    inner_join(passed, by = c("crate_name", "version")) %>%
    inner_join(test_counts, by = c("crate_name")) %>%
    filter(test_count > 0)

has_tests_and_bytecode %>%
    select(crate_name, version) %>%
    write_csv(file.path(stage1_output_dir, "stage2.csv"), col_names = FALSE)

num_tests_and_bytecode <- has_tests_and_bytecode %>% nrow()
stats <- stats %>% add_row(key = "num_crates_had_tests_and_bytecode", value = num_tests_and_bytecode)

stats <- stats %>% write.csv(stats_file, row.names = FALSE, quote = FALSE)

population <- read_csv(file.path(dataset_dir, "population.csv"), show_col_types = FALSE) %>%
select(crate_name, version)

early <- read_csv(file.path(stage1_output_dir, "early_abis.csv"), show_col_types = FALSE) %>% 
    filter(category %in% c("foreign_functions")) %>%
    select(crate_name) %>% 
    unique() %>%
    inner_join(population, by=("crate_name")) %>%
    select(crate_name, version) %>% 
    write_csv(file.path(stage1_output_dir, "had_ffi.csv"))