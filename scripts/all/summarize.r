library(dplyr)
library(readr)
library(stringr)

# if the directory 'build' exists, remove it
if (dir.exists("./build")) {
    unlink("./build", recursive = TRUE)
}
# create the directory 'build'
dir.create("./build")
all_crates <- read_csv(file.path("./data/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage1_failed_download <- read_csv(file.path("./data/results/stage1/failed_download.csv"), col_names = c("crate_name", "version"))
stage1_visited <- read_csv(file.path("./data/results/stage1/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage1 <- all_crates %>% anti_join(stage1_visited, by = c("crate_name", "version")) %>% anti_join(stage1_failed_download, by = c("crate_name", "version")) %>% write_csv("./data/partitions/stage1/missed.csv")

all_crates_stage2 <- read_csv(file.path("./data/compiled/stage1/stage2.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage2_failed_download <- read_csv(file.path("./data/results/stage2/failed_download.csv"), col_names = c("crate_name", "version"), show_col_types = FALSE)
stage2_visited <- read_csv(file.path("./data/results/stage2/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_stage2 <- all_crates_stage2 %>% anti_join(stage2_visited, by = c("crate_name", "version")) %>% anti_join(stage2_failed_download, by = c("crate_name", "version"))

all_tests_stage3 <- read_csv(file.path("./data/compiled/stage2/stage3.csv"), show_col_types = FALSE, col_names = c("test_name", "crate_name", "version"))
all_crates_stage3 <- all_tests_stage3 %>% select(crate_name, version)
stage3_failed_download <- read_csv(file.path("./data/results/stage3/failed_download.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
stage3_visited <- read_csv(file.path("./data/results/stage3/visited.csv"), show_col_types = FALSE, col_names = c("crate_name", "version"))
missed_crates_stage3 <- all_crates_stage3 %>% anti_join(stage3_visited, by = c("crate_name", "version")) %>% anti_join(stage3_failed_download, by = c("crate_name", "version"))

native_comp <- read_csv(file.path("./data/results/stage3/status_native_comp.csv"), col_names = TRUE)
all_tests_stage3_no_version <- all_tests_stage3 %>% select(test_name, crate_name)
missed_tests_stage3 <- all_tests_stage3_no_version %>% anti_join(native_comp, by = c("test_name", "crate_name"))