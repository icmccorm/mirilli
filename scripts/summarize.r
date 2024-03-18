suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(tidyr)
    library(stringr)
    library(ggplot2)
    library(extrafont)
    library(extrafontdb)
})
loadfonts(quiet = TRUE)

build_dir <- file.path("./build")
if (!dir.exists(build_dir)) {
    dir.create(build_dir)
}

if (dir.exists("./build/visuals")) {
    unlink("./build/visuals", recursive = TRUE)
}
dir.create("./build/visuals")

cat("Summarizing stage 1...\n")
source("./scripts/stage1/summarize.r")

cat("Summarizing stage 2...\n")
source("./scripts/stage2/summarize.r")

cat("Summarizing stage 3...\n")
source("./scripts/stage3/summarize.r")

cat("Compiling test outcomes...\n")
source("./scripts/visuals/test_outcomes.r")

cat("Compiling stacked borrows outcomes...\n")
source("./scripts/visuals/stacked_borrow_outcomes.r")

cat("Compiling bugs tables & figures...\n")
source("./scripts/visuals/bugs.r")

cat("Compiling in-text statistics...\n")

stats_file <- file.path(build_dir, "./stats.csv")
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)
stats <- stats %>% add_row(key = "num_crates_unfiltered", value = 125804)
if (file.exists(stats_file)) {
    if (!file.remove(stats_file)) {
        stop("Failed to remove existing stats file")
    }
}
for (file in list.files(file.path(build_dir), full.names = TRUE, recursive = TRUE)) {
    if (str_detect(file, ".stats.csv")) {
        contents <- read_csv(file.path(file), show_col_types = FALSE)
        overlapping_keys <- intersect(stats$key, contents$key)
        if (length(overlapping_keys) > 0) {
            print(paste0("Overlapping keys in ", basename(file), ":\n", paste(overlapping_keys, collapse = ",\n")))
            stop(1)
        }
        stats <- stats %>% bind_rows(contents)
    }
}
stats %>%
    mutate(key = str_to_lower(str_replace_all(str_replace_all(key, " ", "_"), "-", "_"))) %>%
    pivot_wider(names_from = key, values_from = value) %>%
    write.table(file = stats_file, sep = ",", row.names = FALSE, quote = TRUE)
stats %>% write_csv(file.path(build_dir, "stats_long.csv"))
