library(dplyr)
library(readr)
# if ./data/results/tests is not empty, then we can use this to filter
if (file.exists("./data/results/tests/tests.csv")) {
    tests <- read_csv(
        file.path("./data/results/tests/tests.csv"),
        show_col_types = FALSE
    )
    tests %>% filter(had_ffi == 1, exit_code == 1) %>%
        select(test_name, crate_name, version) %>%
        write_csv(file.path("./data/compiled/tests_failed_miri_ffi.csv"))
}