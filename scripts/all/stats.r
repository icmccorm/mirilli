library(dplyr)
library(readr)
library(tidyr)
library(stringr)
build_dir <- file.path("./build")

PLACEHOLDER <- "%%insert%%"
# if the build dir exists, remove it
if(dir.exists(build_dir)) {
    unlink(build_dir, recursive = TRUE)
}

dir.create(build_dir)
stats_file <- file.path(build_dir, "./stats.csv")

stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

stats <- stats %>% add_row(key = "num_crates_unfiltered", value = 125804)

#### Stage 1 ####
all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
num_crates_all <- all %>% nrow()
stats <- stats %>% add_row(key = "num_crates_all", value = num_crates_all)

excluded <- read_csv(file.path("./data/results/exclude.csv"), show_col_types = FALSE)
num_excluded <- excluded %>% nrow()

compiled <- read_csv(file.path("./data/results/stage1/status_comp.csv"), show_col_types = FALSE, col_names = c("crate_name", "version", "exit_code", "instance", "comp")) %>% unique()
num_compiled <- compiled %>%
    filter(exit_code == 0) %>%
    nrow()
num_failed_compilation <- compiled %>%
    filter(exit_code != 0) %>%
    nrow()
stats <- stats %>% add_row(key = "num_crates_compiled", value = num_compiled)
stats <- stats %>% add_row(key = "num_crates_failed_compilation", value = num_failed_compilation)

failed_download <- read_csv(file.path("./data/results/stage1/failed_download.csv"), show_col_types = FALSE, col_names = c("crate_name", "version", "instance", "comp")) %>% unique()
num_failed_download <- failed_download %>% nrow()
stats <- stats %>% add_row(key = "num_crates_failed_download", value = num_failed_download)

had_tests <- read_csv(file.path("./data/results/stage1/has_tests.csv"), show_col_types = FALSE, col_names = c("crate_name", "num_tests")) %>%
    filter(num_tests > 0) %>%
    select(crate_name) %>%
    unique()
num_had_tests <- had_tests %>% nrow()
stats <- stats %>% add_row(key = "num_crates_had_tests", value = num_had_tests)

had_bytecode <- read_csv(file.path("./data/results/stage1/has_bytecode.csv"), show_col_types = FALSE, col_names = c("crate_name", "version", "instance", "comp")) %>% unique()
num_had_bytecode <- had_bytecode %>% nrow()
stats <- stats %>% add_row(key = "num_crates_had_bytecode", value = num_had_bytecode)

visited <- read_csv(file.path("./data/results/stage1/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version")) %>% unique()
missed_stage1 <- all %>%
    anti_join(visited, by = c("crate_name", "version")) %>%
    anti_join(failed_download, by = c("crate_name", "version"))
missed_stage1_count <- missed_stage1 %>% nrow()
if (missed_stage1_count > 1) {
    message(paste0("x - There were ", missed_stage1_count, "missed crates in stage1."))
    failed <- TRUE
} else {
    message("✓ - All crates were visited in stage1")
}

stats <- stats %>% pivot_wider(names_from = ("key")) %>%
# print only column names in quotes
    write.table(file = stats_file, quote = TRUE, sep = ",", row.names = FALSE)