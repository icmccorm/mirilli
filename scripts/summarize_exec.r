library(dplyr)
library(readr)
library(stringr)
if (file.exists("./data/results/execution/errors.csv")) {
    errors <- read_csv(
        file.path("./data/results/execution/errors.csv"),
        show_col_types = FALSE
    )
    errors %>%
        group_by(error_type) %>%
        summarise(count = n()) %>%
        arrange(desc(count)) %>%
        write_csv(file.path("./data/compiled/error_summary.csv"))
    errors %>% 
        group_by(error_text, error_type, error_subtext) %>%
        slice(1) %>%
        write_csv(file.path("./data/compiled/errors_to_examine.csv"))
}