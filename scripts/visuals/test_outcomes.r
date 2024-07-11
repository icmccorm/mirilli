suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(xtable)
})
options(dplyr.summarise.inform = FALSE)

stats <- data.frame(
  key = character(), value = numeric(),
  stringsAsFactors = FALSE
)
stats_path <- file.path("./build/visuals/test_outcomes.stats.csv")

status_labels <- c("Passed", "Timeout", "Test Failed")
error_labels <- c(
  "Using Uninitialized Memory", "Borrowing Violation",
  "Other Error"
)
non_error_results <- c(
  status_labels, error_labels, "Unsupported Operation in LLI",
  "Unsupported Operation in Miri", "Timeout", "Scalar Size Mismatch",
  "Unwinding Past Topmost Frame"
)
final_categories <- c(error_labels, status_labels, "Unsupported Operation")

errors <- read_csv(
  file.path("./build/stage3/errors.csv"),
  show_col_types = FALSE
)

errors_stack <- errors %>%
  select(crate_name, test_name, memory_mode, error_type_stack, error_text_stack) %>%
  rename(error_type = error_type_stack, error_text = error_text_stack) %>%
  mutate(borrow_mode = "stack")

errors_tree <- errors %>%
  select(crate_name, test_name, memory_mode, error_type_tree, error_text_tree) %>%
  rename(error_type = error_type_tree, error_text = error_text_tree) %>%
  mutate(borrow_mode = "tree")

results <- bind_rows(errors_stack, errors_tree)

unsupp <- results %>% 
    filter(error_type %in% c("Unsupported Operation", "Scalar Size Mismatch", "LLI Internal Error"))
unsupp_test_count <- unsupp %>% select(crate_name, test_name) %>% unique() %>% nrow()

filter_unsupp <- function(df) {
    df %>%
        mutate(error_text = ifelse(str_detect(error_text, "can't call foreign function"), "dyn_asm", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "is not supported for use in shims"), "llvm_type_shim", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "scalar size mismatch"), "llvm_type_shim", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "only supports float and double"), "x86_fp80", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "x86_fp80"), "x86_fp80", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "Inline assembly"), "dyn_asm", error_text)) %>%
        mutate(error_text = ifelse(str_detect(error_text, "LLVM instruction not supported"), "inst", error_text)) %>%
        mutate(error_text = ifelse(error_text %in% c("x86_fp80", "dyn_asm", "inst", "llvm_type_shim"), error_text, "other"))
}

unsupp_avg <- unsupp %>% 
    filter_unsupp %>%
    group_by(error_text, borrow_mode, memory_mode) %>% 
    summarize(n= n()) %>%
    group_by(error_text) %>%
    summarize(n = mean(n)) %>%
    mutate(n = round(n / unsupp_test_count * 100)) %>%
    rename(key = error_text, value = n) %>%
    mutate(key = paste0("error_avg_percentage_unsupp_", key))

stats <- stats %>% bind_rows(unsupp_avg)

results_ungrouped <- results %>%
  group_by(memory_mode, borrow_mode, error_type) %>%
  summarize(n = n()) %>%
  arrange(desc(n)) %>%
  mutate(
    error_type = ifelse(
      error_type == "LLI Internal Error", "Unsupported Operation in LLI",
      error_type
    )
  ) %>%
  mutate(
    error_type = ifelse(
      error_type %in% c("Unsupported Operation", "Scalar Size Mismatch"), "Unsupported Operation in Miri",
      error_type
    )
  ) %>%
  mutate(
    error_type = ifelse(
      is.na(error_type),
      "Passed", error_type
    )
  ) %>%
  mutate(
    error_type = ifelse(
      !(error_type %in% non_error_results), "Other Error",
      error_type
    )
  ) %>%
  group_by(memory_mode, borrow_mode, error_type) %>%
  summarize(n = sum(n)) %>%
  group_by(memory_mode, borrow_mode) %>%
  mutate(
    n_percent = round(
      100 * n / sum(n),
      1
    )
  ) %>%
  ungroup()

test_results_grouped <- results_ungrouped %>%
  filter((str_detect(error_type, "Unsupported Operation in"))) %>%
  mutate(error_type = "Unsupported Operation") %>%
  group_by(memory_mode, borrow_mode, error_type) %>%
  summarize(
    n = sum(n),
    n_percent = sum(n_percent)
  ) %>%
  bind_rows(results_ungrouped) %>%
  ungroup()

test_results_averaged <- test_results_grouped %>%
  mutate(
    error_type = ifelse(
      error_type %in% error_labels, "Error",
      error_type
    )
  ) %>%
  group_by(error_type, memory_mode, borrow_mode) %>%
  summarize(
    n = sum(n),
    n_percent = sum(n_percent)
  ) %>%
  group_by(error_type) %>%
  summarize(n_percent = mean(n_percent)) %>%
  rename(key = error_type, value = n_percent) %>%
  mutate(key = paste0("error_avg_percentage_", str_to_lower(key))) %>%
  mutate(value = round(value, 0)) %>%
  mutate(key = str_replace_all(key, " ", "_"))

stats <- stats %>%
  bind_rows(test_results_averaged)

test_results_table <- test_results_grouped %>%
  mutate(key = paste(memory_mode, borrow_mode, sep = "_")) %>%
  select(-memory_mode, -borrow_mode) %>%
  mutate(value = paste0(n_percent, "%", " (", n, ")")) %>%
  select(-n, -n_percent) %>%
  spread(key = key, value = value) %>%
  mutate_all(
    ~ ifelse(
      is.na(.),
      "-", .
    )
  ) %>%
  filter(error_type %in% final_categories) %>%
  mutate(error_type = factor(error_type, levels = final_categories)) %>%
  arrange(error_type) %>%
  write_csv(file.path("./build/visuals/test_results.csv"))

stats %>%
  write_csv(stats_path)
