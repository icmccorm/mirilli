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
    ub <- errors %>% 
        filter(error_type == "Undefined Behavior") %>%
        unique()
    ub$ub_type <- NA
    ub$ub_type[grepl("trying to retag", ub$error_text)] <- "Stacked Borrows - Failed Retag"
    ub$ub_type[grepl("was dereferenced after this allocation got freed", ub$error_text)] <- "Use-After-Free"
    ub$ub_type[grepl("attempting a write access", ub$error_text)] <- "Stacked Borrows - Failed Write"
    ub$ub_type[grepl("attempting a read access", ub$error_text)] <- "Stacked Borrows - Failed Read"
    ub$ub_type[grepl("constructing invalid value", ub$error_text)] <- "Constructing Invalid Value"
    ub$ub_type[grepl("unwinding past the topmost frame of the stack ", ub$error_text)] <- "Invalid Unwinding"
    ub$ub_type[is.na(ub$ub_type)] <- "Internal Error"
    ub_crates_to_investigate <- ub %>% 
        select(crate, ub_type, test) %>%
        write_csv(file.path("./data/compiled/tests_with_ub.csv"))
    errors %>% 
        group_by(error_text, error_type, error_subtext) %>%
        slice(1) %>%
        write_csv(file.path("./data/compiled/errors_to_examine.csv"))
}