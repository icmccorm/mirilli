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

captured_abi_subset <- bind_rows(late_names, early_names) %>%
    inner_join(all, by = ("crate_name")) %>%
    unique() %>%
    write_csv(file.path("./data/compiled/abi_subset.csv"))

early_abis %>%
    select(crate_name) %>%
    unique() %>%
    inner_join(all, by = ("crate_name")) %>%
    write_csv(file.path("./data/compiled/abi_subset_early.csv"))
problems()