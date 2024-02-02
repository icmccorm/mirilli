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
stats %>% pivot_wider(names_from = key, values_from = value) %>% 
    write.table(file = stats_file, sep = ",", row.names = FALSE, quote = TRUE)