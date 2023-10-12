library(dplyr)
library(readr)

# if ./data/results/tests is not empty, then we can use this to filter
if (file.exists("./data/results/stage2/tests.csv")) {
    tests <- read_csv(
        file.path("./data/results/stage2/tests.csv"),
        show_col_types = FALSE,
        col_names = c("exit_code", "had_ffi", "test_name", "crate_name")
    )
    population <- read_csv(
        file.path("./data/all.csv"),
        show_col_types = FALSE,
        col_names = c("crate_name", "version")
    )
    failed_miri_ffi <- tests %>%
        filter(had_ffi == 0, exit_code == 1) %>%
        select(test_name, crate_name) %>%
        inner_join(population, by = c("crate_name"))
    failed_miri_ffi %>% select(crate_name) %>% unique() %>% nrow()
    failed_miri_ffi %>% write_csv(file.path("./data/compiled/stage2/stage3.csv"), col_names = FALSE)
}
