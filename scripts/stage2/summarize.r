suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
})

stage2_root <- file.path("./build/stage2")
if (!dir.exists(stage2_root)) {
    dir.create(stage2_root)
}
stats_file <- file.path(stage2_root, "./stats.csv")
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

tests <- read_csv(
    file.path("./results/stage2/tests_cleaned.csv"),
    show_col_types = FALSE,
    col_names = c("exit_code", "had_ffi", "test_name", "crate_name")
) %>%
    filter(test_name != "")

population <- read_csv(file.path("./results/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version", "last_updated", "downloads", "percentile_downloads", "avg_daily_downloads", "percentile_daily_download")) %>%
select(crate_name, version)

test_count_overall <- tests %>%
    select(test_name, crate_name) %>%
    unique() %>%
    nrow()
stats <- stats %>% add_row(key = "test_count_overall", value = test_count_overall)

passed <- tests %>%
    filter(exit_code == 0) %>%
    nrow()
timed_out <- tests %>%
    filter(exit_code == 124) %>%
    nrow()

disabled_tests <- tests %>%
    filter(exit_code == -1)

num_disabled <- disabled_tests %>% nrow()

disabled_tests %>%
    inner_join(population, by = c("crate_name")) %>%
    select(test_name, crate_name, version) %>%
    unique() %>%
    write_csv(file.path(stage2_root, "./stage2-ignored.csv"))

timed_out <- tests %>%
    filter(exit_code == 124) %>%
    nrow()

failed <- tests %>%
    filter(exit_code > 0, exit_code != 124) %>%
    unique() %>%
    nrow()

failed_miri_ffi <- tests %>%
    filter(had_ffi == 0, exit_code == 1) %>%
    select(test_name, crate_name) %>%
    inner_join(population, by = c("crate_name"))

failed_miri_ffi_count <- failed_miri_ffi %>%
    unique() %>%
    nrow()

failed_miri_ffi %>% write_csv(file.path(stage2_root, "./stage3.csv"), col_names = FALSE)

stats <- stats %>% add_row(key = "tests_failed_ffi", value = failed_miri_ffi_count)
stats <- stats %>% add_row(key = "tests_failed", value = failed)
stats <- stats %>% add_row(key = "tests_passed", value = passed)
stats <- stats %>% add_row(key = "tests_timed_out", value = timed_out)
stats <- stats %>% add_row(key = "tests_disabled", value = num_disabled)
stats <- stats %>% write.csv(stats_file, row.names = FALSE, quote = FALSE)

