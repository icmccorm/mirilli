library(dplyr)
library(readr)
library(tidyr)
library(stringr)

stats_file <- file.path("./compiled/stats.csv")
if (file.exists(stats_file)) {
    file.remove(stats_file)
}

stats <- data.frame(key = character(), value = character(), stringsAsFactors = FALSE)

stats <- stats %>% add_row(key = "rustc_nightly_toolchain", value = "nightly-2023-09-25")
stats <- stats %>% add_row(key = "rustc_nightly_version", value = "1.74")
stats <- stats %>% add_row(key = "miri_commit_hash", value = "1a82975")
stats <- stats %>% add_row(key = "clippy_commit_hash", value = "5eb7604")
stats <- stats %>% add_row(key = "crates_io_date", value = "2021-09-20")
stats <- stats %>% add_row(key = "num_crates_unfiltered", value = "")


all <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
num_crates_all <- all %>% nrow()
stats <- stats %>% add_row(key = "num_crates_all", value = as.character(num_crates_all))
