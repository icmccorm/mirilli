library(dplyr)
library(readr)

stage1_input_dir <- file.path("./data/results/stage1")
stage1_output_dir <- file.path("./data/compiled/stage1")


comp_status <- read_csv(file.path(stage1_input_dir, "status_comp.csv"), col_names = c("crate_name", "version", "exit_code"), show_col_types = FALSE)
lint_status <- read_csv(file.path(stage1_input_dir, "status_lint.csv"), col_names = c("crate_name", "version", "exit_code"), show_col_types = FALSE)

num_comp_all <- comp_status %>% nrow()
num_comp_passed <- comp_status %>% filter(exit_code == 0) %>% nrow()
percent_comp_passed <- num_comp_passed / num_comp_all * 100

num_lint_all <- lint_status %>% nrow()
num_lint_passed <- lint_status %>% filter(exit_code == 0) %>% nrow()
percent_lint_passed <- num_lint_passed / num_lint_all * 100

if (percent_lint_passed < 50 || percent_comp_passed < 50) {
    stop("Too many crates failed to compile or lint")
}

comp_status %>% filter(exit_code == 124) %>% nrow()
comp_status %>% filter(exit_code == 101) %>% nrow()
comp_status %>% group_by(exit_code) %>% summarize(n= n())
test_counts <- read_csv(file.path(stage1_input_dir, "has_tests.csv"), col_names = c("crate_name", "test_count"), show_col_types = FALSE)

has_bytecode <- read_csv(file.path(stage1_input_dir, "has_bytecode.csv"), col_names = c("crate_name", "version"), show_col_types = FALSE) %>% arrange(crate_name)

has_tests_and_bytecode <- has_bytecode %>%
    inner_join(test_counts, by = c("crate_name")) %>%
    filter(test_count > 0) %>%
    select(crate_name, version) %>%
    write_csv(file.path(stage1_output_dir, ".csv"), col_names = FALSE)