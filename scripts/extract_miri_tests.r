library(dplyr)
library(readr)
# if ./data/results/tests is not empty, then we can use this to filter
if (file.exists("./data/results/tests/tests.csv")) {
    tests <- read_csv(
        file.path("./data/results/tests/tests.csv"),
        show_col_types = FALSE
    )
    tests %>% filter(had_ffi == 0, exit_code == 1) %>%
        select(test_name, crate_name) %>%
        write_csv(file.path("./data/compiled/tests_failed_miri_ffi.csv"))
    total_visited <- tests %>% nrow()
    tests %>% filter(had_ffi==1, exit_code==124)
    tests %>% group_by(had_ffi, exit_code) %>% summarize(n=round(n()/total_visited * 100, 1))

    tests %>% filter(had_ffi == 0, exit_code == 1) %>% group_by(crate_name) %>% summarize(n=n()) %>%
        arrange(desc(n)) %>% head(10)

}
