library(dplyr)
library(readr)
all <- read_csv(file.path("./dataset/population.csv"), show_col_types = FALSE) %>%
  select(crate_name, version)

errors_stack <- read_csv("./dataset/stage3/errors_stack.csv")
roots_stack <- read_csv("./dataset/stage3/stack_error_roots.csv")

rerun_stack <- errors_stack %>%
  filter(error_text == "using uninitialized data, but this operation requires initialized memory") %>%
  full_join(roots_stack, by = c("crate_name", "test_name")) %>%
  filter(!is.na(error_root), !is.na(crate_name), !is.na(test_name)) %>%
  inner_join(all, by = c("crate_name")) %>%
  select(test_name, crate_name, version)

errors_tree <- read_csv("./dataset/stage3/errors_tree.csv")
roots_tree <- read_csv("./dataset/stage3/tree_error_roots.csv")

rerun_tree <- errors_tree %>%
  filter(error_text == "using uninitialized data, but this operation requires initialized memory") %>%
  full_join(roots_tree, by = c("crate_name", "test_name")) %>%
  filter(!is.na(error_root), !is.na(crate_name), !is.na(test_name)) %>%
  inner_join(all, by = c("crate_name")) %>%
  select(test_name, crate_name, version)

rerun_uninit_all <- bind_rows(rerun_stack, rerun_tree) %>%
  unique() %>%
  write_csv("./build/stage3/uninit.csv", col_names = FALSE)
