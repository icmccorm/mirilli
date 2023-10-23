library(dplyr)
library(readr)
library(stringr)
filter_errors <- function(df) {
    df <- df %>% filter(!(error_type %in% c("LLI Internal Error", "Unsupported Operation")))
    # keep one row per unique combination of crate_name, full_error_text, and error_root
    # this is because the same error can be reported multiple times in the same crate
    df %>%
        group_by(crate_name, full_error_text, error_root) %>%
        slice(1) %>%
        ungroup()
}

root <- file.path("./data/results/stage3/")
stack_errors <- read_csv(file.path(root, "errors_stack.csv"), show_col_types = FALSE)
problems(stack_errors)
stack_errors_roots <- read_csv(file.path(root, "stack_error_roots.csv"), show_col_types = FALSE)
stack_errors <- stack_errors %>%
    left_join(stack_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors()
stack_errors %>% write_csv(file.path("./test.csv"))
tree_errors <- read_csv(file.path(root, "errors_tree.csv"), show_col_types = FALSE)
tree_errors_roots <- read_csv(file.path(root, "tree_error_roots.csv"), show_col_types = FALSE)
tree_errors <- tree_errors %>%
    left_join(tree_errors_roots, by = c("crate_name", "test_name")) %>%
    filter_errors()




if (file.exists("./data/results/stage3/errors.csv")) {
    errors <- read_csv(
        file.path("./data/results/execution/errors.csv"),
        show_col_types = FALSE
    )
    # if the error type begins with "Aborting due to", then replace the entire error_type with "Compilation Error"
    errors$error_type <- str_replace(errors$error_type, "^aborting due to.*$", "Unknown Abort")
    errors %>%
        group_by(error_type) %>%
        summarise(count = n()) %>%
        mutate(error_type = str_to_title(error_type)) %>%
        arrange(desc(count)) %>%
        write_csv(file.path("./data/compiled/error_summary.csv"))
    errors %>%
        group_by(crate, test) %>%
        summarize(n = n()) %>%
        arrange(desc(n))
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
    ub$ub_type[grepl("using uninitialized data, but this operation requires initialized memory", ub$error_text)] <- "Uninitialized Memory"
    ub$ub_type[is.na(ub$ub_type)] <- "Internal Error"

    ub %>%
        group_by(ub_type) %>%
        summarise(count = n()) %>%
        mutate(error_type = str_to_title(ub_type)) %>%
        arrange(desc(count)) %>%
        write_csv(file.path("./data/compiled/ub_summary.csv"))

    ub_crates_to_investigate <- ub %>%
        select(crate, ub_type, test) %>%
        write_csv(file.path("./data/compiled/tests_with_ub.csv"))
    errors %>%
        group_by(error_text, error_type, error_subtext) %>%
        slice(1) %>%
        filter(error_subtext != "Unsupported function call") %>%
        write_csv(file.path("./data/compiled/errors_to_examine.csv"))
}
