library(dplyr)
library(readr)
if (file.exists("./data/results/tests/visited.csv")) {
    visited <- read_csv(
        file.path("./data/results/tests/visited.csv"),
        show_col_types = FALSE,
        header = FALSE
    )
    has_bytecode <- read_csv(
        file.path("./data/results/has_bytecode.csv"),
        show_col_types = FALSE,
        header = FALSE
    )
    # ensure that the two are equal
    stopifnot(
        nrow(visited) == nrow(has_bytecode),
        all(visited$crate_name == has_bytecode$crate_name)
    )
}


# if ./data/results/tests is not empty, then we can use this to filter
if (file.exists("./data/results/tests/tests.csv")) {


    tests <- read_csv(
        file.path("./data/results/tests/tests.csv"),
        show_col_types = FALSE
    )
    population <- read_csv(
        file.path("./data/all.csv"),
        show_col_types = FALSE
    )
    failed_miri_ffi <- tests %>%
        filter(had_ffi == 0, exit_code == 1) %>%
        select(test_name, crate_name) %>%
        inner_join(population, by = c("crate_name"))

    # find the sample size needed for a 95% confidence interval
    # with a population size equal to the number of rows in failed_miri_ffi
    # and a margin of error of 5%
    sample_size <- ceiling(
        (1.96^2 * nrow(failed_miri_ffi) * 0.5 * 0.5) / (0.05^2 * (nrow(failed_miri_ffi) - 1) + 1.96^2 * 0.5 * 0.5)
    )
    failed_miri_ffi %>%
        sample_n(sample_size) %>%
        write_csv(file.path("./data/compiled/tests_failed_miri_sample.csv"))
    failed_miri_ffi %>% write_csv(file.path("./data/compiled/tests_failed_miri_ffi.csv"))
}
