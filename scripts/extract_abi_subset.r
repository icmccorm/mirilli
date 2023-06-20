library(dplyr)
library(readr)

late_abis_path <- file.path("./data/compiled/late_abis.csv")
late_abis <- read_csv(
    late_abis_path,
    show_col_types = FALSE
)

early_abis_path <- file.path("./data/compiled/early_abis.csv")
early_abis <- read_csv(
    early_abis_path,
    show_col_types = FALSE
)

all_path <- file.path("./data/all.csv")
all <- read_csv(
    all_path,
    show_col_types = FALSE
)

external_ffi_bindings_path <- file.path("./data/external_ffi_bindings.csv")
external_ffi_bindings <- read_csv(
    external_ffi_bindings_path,
    show_col_types = FALSE
)

counts_path <- file.path("./data/results/count.csv")
counts <- read_csv(
    counts_path,
    show_col_types = FALSE
)
counts %>%
    filter(ffi_c_count > 0) %>%
    filter((test_count + bench_count) > 0) %>%
    write_csv(file.path("./data/compiled/grep_c_ffi_tests.csv"))

counts %>%
    filter(ffi_count > 0) %>%
    filter((test_count + bench_count) > 0) %>%
    write_csv(file.path("./data/compiled/grep_ffi_tests.csv"))

late_names <- late_abis %>%
    select(crate_name) %>%
    unique()
early_names <- early_abis %>%
    select(crate_name) %>%
    unique()
# select names in early_names that don't appear in late_names
early_names_failed_late <- early_names %>%
    anti_join(late_names, by = ("crate_name"))
# write out
early_names_failed_late %>%
    inner_join(all, by = ("crate_name")) %>%
    write_csv(file.path("./data/compiled/early_names_failed_late.csv"))


captured_abi_subset <- bind_rows(late_names, early_names) %>%
    inner_join(all, by = ("crate_name")) %>%
    unique() %>%
    write_csv(file.path("./data/compiled/abi_subset.csv"))
unmerged_output_path <- file.path("./data/compiled/abi_subset.csv")
captured_abi_subset %>% write_csv(unmerged_output_path)


early_abis %>%
    select(crate_name) %>%
    unique() %>%
    inner_join(all, by = ("crate_name")) %>%
    write_csv(file.path("./data/compiled/abi_subset_early.csv"))

problems()