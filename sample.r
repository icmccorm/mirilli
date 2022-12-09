library(dplyr)
library(readr)
library(tidyr)  
options(dplyr.summarise.inform = FALSE)

all_path <- file.path("./data/all.csv")
all <- read_csv(
    all_path,
    show_col_types = FALSE
)
einfo_path <- file.path("./data/locations/error_info.csv")
einfo <- read_csv(
    einfo_path,
    show_col_types = FALSE
)
eloc_path <- file.path("./data/locations/error_locations.csv")
eloc <- read_csv(
    eloc_path,
    show_col_types = FALSE
)
discrim_path <- file.path("./data/discriminants.csv")
discrim <- read_csv(
    discrim_path,
    show_col_types = FALSE
)
ninfo <- einfo %>% select(crate_name, err_id) %>% unique %>% nrow
nloc <- eloc %>% select(crate_name, err_id) %>% unique %>% nrow
if (ninfo != nloc) {
    stop("Mismatching number of unique errors in info and locations tables.")
}
errors <- einfo %>%
    inner_join(eloc, by = c("err_id", "crate_name")) %>%
    inner_join(discrim, by = c("discriminant")) %>%
    filter(type_name == "Adt")
sample <- errors %>%
    group_by(err_text, category) %>%
    slice_sample(n = 1) %>%
    ungroup()
sample %>% write_csv(file.path("./coding/samples/improper_types.csv"))