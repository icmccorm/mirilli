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

late_names <- late_abis %>% select(crate_name)
early_names <- early_abis %>% select(crate_name)
captured_abi_subset <- bind_rows(late_names, early_names) %>%
    unique() %>%
    inner_join(all, by = ("crate_name")) %>%
    write_csv(file.path("./data/abi_subset.csv"))

# merge all rows from captured abi subset with external ffi bindings and keep unique ones

unmerged_output_path <- file.path("./data/captured_abi_subset.csv")

captured_abi_subset %>% write_csv(unmerged_output_path)

output_path <- file.path("./data/abi_subset.csv")

combined <- bind_rows(captured_abi_subset, external_ffi_bindings) %>%
    unique() %>%
    write_csv(output_path)

problems()
