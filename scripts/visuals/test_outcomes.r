suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(stringr)
    library(xtable)
})
options(dplyr.summarise.inform = FALSE)

stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)
stats_path <- file.path("./build/visuals/test_outcomes.stats.csv")
status_labels <- c("Passed", "Timeout", "Test Failed")
error_labels <- c("Using Uninitialized Memory", "Borrowing Violation", "Other Error")
non_error_results <- c(status_labels, error_labels, "Unsupported Operation in LLI", "Unsupported Operation in Miri", "Timeout", "Scalar Size Mismatch", "Unwinding Past Topmost Frame")
non_unsupported_results <- c(error_labels, status_labels)
final_categories <- c(error_labels, status_labels, "Unsupported Operation")

test_results <- read_csv(file.path("./build/stage3/errors.csv"), show_col_types = FALSE)

results_stack <- test_results %>%
    select(crate_name, test_name, memory_mode, error_type_stack) %>%
    rename(error_type = error_type_stack) %>%
    mutate(borrow_mode = "stack")

results_tree <- test_results %>%
    select(crate_name, test_name, memory_mode, error_type_tree) %>%
    rename(error_type = error_type_tree) %>%
    mutate(borrow_mode = "tree")

results <- bind_rows(results_stack, results_tree)

test_results_ungrouped <- results %>%
    group_by(memory_mode, borrow_mode, error_type) %>%
    summarize(n = n()) %>%
    arrange(desc(n)) %>%
    mutate(error_type = ifelse(error_type == "LLI Internal Error", "Unsupported Operation in LLI", error_type)) %>%
    mutate(error_type = ifelse(error_type == "Unsupported Operation", "Unsupported Operation in Miri", error_type)) %>%
    mutate(error_type = ifelse(is.na(error_type), "Passed", error_type)) %>%
    mutate(error_type = ifelse(!(error_type %in% non_error_results), "Other Error", error_type)) %>%
    group_by(memory_mode, borrow_mode, error_type) %>%
    summarize(n = sum(n)) %>%
    group_by(memory_mode, borrow_mode) %>%
    mutate(n_percent = round(100 * n / sum(n), 1)) %>%
    ungroup()

test_results_grouped <- test_results_ungrouped %>%
    filter(!(error_type %in% non_unsupported_results)) %>%
    mutate(error_type = "Unsupported Operation") %>%
    group_by(memory_mode, borrow_mode, error_type) %>%
    summarize(n = sum(n), n_percent = sum(n_percent)) %>%
    bind_rows(test_results_ungrouped) %>%
    ungroup()

test_results_averaged <- test_results_grouped %>%
    mutate(error_type = ifelse(error_type %in% error_labels, "Error", error_type)) %>%
    group_by(error_type, memory_mode, borrow_mode) %>%
    summarize(n = sum(n), n_percent = sum(n_percent)) %>%
    group_by(error_type) %>%
    summarize(n_percent = mean(n_percent)) %>%
    rename(key = error_type, value = n_percent) %>%
    mutate(key = paste0("error_avg_percentage_", str_to_lower(key))) %>%
    mutate(value = round(value, 0)) %>%
    mutate(key = str_replace_all(key, " ", "_"))

stats <- stats %>% bind_rows(test_results_averaged)

test_results_table <- test_results_grouped %>%
    mutate(key = paste(memory_mode, borrow_mode, sep = "_")) %>%
    select(-memory_mode, -borrow_mode) %>%
    mutate(value = paste0(n_percent, "%", " (", n, ")")) %>%
    select(-n, -n_percent) %>%
    spread(key = key, value = value) %>%
    mutate_all(~ ifelse(is.na(.), "-", .)) %>%
    filter(error_type %in% final_categories) %>%
    mutate(error_type = factor(error_type, levels = final_categories)) %>%
    arrange(error_type) %>%
    write_csv(file.path("./build/visuals/test_results.csv"))

stats %>% write_csv(stats_path)
