suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(tidyr)
    library(stringr)
})


build_dir <- file.path("./build")
if (!dir.exists(build_dir)) {
    dir.create(build_dir)
}
source("./scripts/stage1/summarize.r")
source("./scripts/stage2/summarize.r")
source("./scripts/stage3/summarize.r")
stats_file <- file.path(build_dir, "./stats.csv")
if (file.exists(stats_file)) {
    if (!file.remove(stats_file)) {
        stop("Failed to remove existing stats file")
    }
}
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)
for (file in list.files(file.path(build_dir), full.names = TRUE, recursive = TRUE)) {
    if (str_detect(file, "stats.csv")) {
        stats <- stats %>% bind_rows(read_csv(file.path(file), show_col_types = FALSE))
    }
}
stats <- stats %>% add_row(key = "num_crates_unfiltered", value = 125804)

bugs <- read_csv(file.path("./build/stage3/bugs.csv"), show_col_types = FALSE) %>%
    select(crate_name, version, test_name, error_type, issue, pull_request, commit) %>%
    filter(!is.na(pull_request) | !is.na(commit) | !is.na(issue))

bug_stats <- bugs %>%
    group_by(error_type) %>%
    summarize(n = n()) %>%
    mutate(error_type = str_to_lower(error_type)) %>%
    mutate(error_type = str_replace_all(error_type, " ", "_")) %>%
    mutate(error_type = str_replace_all(error_type, "<T>::", "_")) %>%
    mutate(error_type = str_replace_all(error_type, "()", "")) %>%
    mutate(error_type = paste0("error_count_", error_type)) %>%
    rename(key = error_type, value = n)


errors <- read_csv(file.path("./build/stage3/errors.csv")) %>%
    filter(memory_mode == "zeroed") %>%
    mutate(error_type_stack == ifelse(grepl(error_text_stack, ) == "deallocating alloc, which is", "Cross-Language Deallocation", error_type_stack)) %>%
    group_by(error_type_stack) %>%
    summarize(n = n()) %>%
    arrange(desc(n)) %>%
    mutate(error_type_stack = ifelse(error_type_stack == "LLI Internal Error", "Unsupported Operation in LLI", error_type_stack)) %>%
    mutate(error_type_stack = ifelse(error_type_stack == "Unsupported Operation", "Unsupported Operation in Miri", error_type_stack)) %>%
    mutate(error_type_stack = ifelse(is.na(error_type_stack), "Passed", error_type_stack)) 



stats <- stats %>% bind_rows(bug_stats)
stats <- stats %>% add_row(key = "num_bugs", value = nrow(bugs))

stats %>%
    pivot_wider(names_from = key, values_from = value) %>%
    write.table(file = stats_file, sep = ",", row.names = FALSE, quote = TRUE)
