library(dplyr)
library(readr)
library(tidyr)
options(dplyr.summarise.inform = FALSE)
all_path <- file.path("./data/all.csv")
all <- read_csv(
    all_path,
    show_col_types = FALSE
)
downloads_path <- file.path("./data/download_counts_1yr.csv")
downloads <- read_csv(
    downloads_path,
    show_col_types = FALSE
)
finished_early_path <- file.path("./data/finished_early.csv")
finished_early <- read_csv(
    finished_early_path,
    show_col_types = FALSE
)
finished_late_path <- file.path("./data/finished_late.csv")
finished_late <- read_csv(
    finished_late_path,
    show_col_types = FALSE
)
foreign_abis_path <- file.path("./data/foreign_module_abis.csv")
foreign_abis <- read_csv(
    foreign_abis_path,
    show_col_types = FALSE
) %>% filter(abi == "C")

early_downloads <- finished_early %>% 
    inner_join(downloads, by=c("name")) %>% 
    inner_join(foreign_abis, by=c("name")) %>% 
    arrange(desc(num_downloads)) %>% 
    slice(1:20) %>% select(name, count)

coding_sample_path <- file.path("./coding/samples/crates.csv")
early_downloads %>% write_csv(coding_sample_path)

discriminant_counts_path <- file.path("./data/category_error_counts.csv")
discriminant_counts <- read_csv(
    discriminant_counts_path,
    show_col_types = FALSE
)

discriminmant_names_path <- file.path("./data/discriminants.csv")
discriminant_names <- read_csv(
    discriminmant_names_path,
    show_col_types = FALSE
)

named_counts <- discriminant_counts %>% inner_join(discriminant_names, by=c("id"))
decls <- named_counts %>% filter(category %in% c("foreign_functions"))
defns <- named_counts %>% filter(category %in% c("rust_functions"))
decls_items <- named_counts %>% filter(category %in% c("static_items"))

decls_items_counts <- decls_items %>% group_by(name) %>% summarize(fi_count = sum(count)) %>% unique
decls_counts <- decls %>% group_by(name) %>% summarize(ff_count = sum(count)) %>% unique
defns_counts <- defns %>% group_by(name) %>% summarize(ef_count = sum(count)) %>% unique

final <- discriminant_names %>% left_join(decls_counts, by=c("name")) %>% left_join(decls_items_counts, by=c("name")) %>% left_join(defns_counts, by=c("name")) %>% mutate(across(where(is.numeric), ~ replace_na(.x, 0)))
final %>% write_csv(file.path("./data/compiled/error_counts.csv"))

string_err_counts_path <- file.path("./data/string_error_counts.csv")
string_err_counts <- read_csv(
    string_err_counts_path,
    show_col_types = FALSE
)

named_string_err_counts <- string_err_counts %>% inner_join(discriminant_names, by=c("id"))

to_resample <- named_string_err_counts %>% filter(name == "Adt") %>% 
    group_by(text, category) %>% 
    sample_n(1) %>% 
    summarize(crate_name = crate_name, text=text, category = category)

all$crate_name <- all$name
versions <- to_resample %>% inner_join(all, by=c("crate_name")) %>%  ungroup(text) %>% select(crate_name, version) %>% distinct
versions %>% write_csv(file.path("./data/partitions/partition10.csv"))