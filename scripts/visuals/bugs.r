suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(xtable)
  library(ggplot2)
  library(ggrepel)
  library(extrafont)
  library(extrafontdb)
  library(RColorBrewer)
})
loadfonts(quiet = TRUE)
options(dplyr.summarise.inform = FALSE)

stats_file <- file.path("./build/visuals/bugs.stats.csv")
stats <- data.frame(key = character(), value = numeric(), stringsAsFactors = FALSE)

as_link <- function(link_text, url) {
  return(paste0("\\buglink{", url, "}{", link_text, "}"))
}

parse_links <- function(links, item_text, parse_fn) {
  links %>%
    sapply(function(issue_text) {
      as.list(strsplit(issue_text, ",")[[1]]) %>%
        sapply(function(x) {
          parse_fn(trimws(x), item_text)
        })
    })
}


gh_id_parse_fn <- function(link, item_text) {
  if (!is.na(link) && grepl(paste0(item_text, "/[0-9]+$"), link)) {
    issue_number <- str_extract(link, "[0-9]+$")
    as_link(paste0("\\#", issue_number), link)
  } else {
    ""
  }
}
commit_hash_parse_fn <- function(link, item_text) {
  if (!is.na(link) && grepl(paste0(item_text, "/[0-9a-fA-F]+$"), link)) {
    issue_number <- str_extract(link, "[0-9a-fA-F]+$")
    # get the first 7 characters of the commit hash
    as_link(substr(issue_number, 1, 7), link)
  } else {
    ""
  }
}

all_errors <- read_csv(file.path("./build/stage3/errors.csv"), show_col_types = FALSE)

ownership <- c("Tree Borrows")
memory <- c("Memory Leaked", "Out of Bounds Access", "Cross-Language Free")
typing <- c("Using Uninitialized Memory", "Unaligned Reference", "Invalid Enum Tag", "Incorrect FFI Binding")

bugs <- read_csv(file.path("./dataset/bugs.csv"), show_col_types = FALSE) %>%
  select(bug_id, crate_name, version, root_crate_name, root_crate_version, test_name, annotated_error_type, fix_loc, issue, pull_request, commit, bug_type_override, memory_mode, error_loc_override, error_type_override) %>%
  left_join(all_errors, by = c("crate_name", "version", "test_name", "memory_mode")) %>%
  mutate(
    error_type_tree = ifelse(!is.na(bug_type_override), bug_type_override, error_type_tree)
  ) %>%
  mutate(error_type = ifelse(str_equal(error_type_tree, "Borrowing Violation"), "Tree Borrows", error_type_tree)) %>%
  mutate(error_type = ifelse(!is.na(error_type_override), error_type_override, error_type)) %>%
  filter(!is.na(pull_request) | !is.na(commit) | !is.na(issue)) %>%
  mutate(error_loc = ifelse(is_foreign_error_tree | is_foreign_error_stack, "LLVM", "Rust")) %>%
  mutate(error_loc = ifelse(error_type == "Incorrect FFI Binding", "Binding", error_loc)) %>%
  mutate(error_loc = ifelse(!is.na(error_loc_override), error_loc_override, error_loc)) %>%
  mutate(bug_category = ifelse(error_type %in% ownership, "Ownership", ifelse(error_type %in% memory, "Allocation", ifelse(error_type %in% typing, "Typing", NA)))) %>%
  mutate(error_type = ifelse(error_type == "Incorrect FFI Binding", "Incorrect Binding", error_type)) %>%
  mutate(error_type = ifelse(error_type == "Unaligned Reference", "Alignment", error_type)) %>%
  mutate(error_type = ifelse(error_type == "Using Uninitialized Memory", "Uninitialized Memory", error_type)) %>%
  mutate(error_type = ifelse(error_type == "Tree Borrows Violation", "Tree Borrows", error_type)) %>%
  select(
    bug_id,
    crate_name,
    version,
    annotated_error_type,
    root_crate_name,
    root_crate_version,
    test_name,
    error_type,
    error_loc,
    fix_loc,
    issue,
    pull_request,
    commit,
    bug_category
  )
location_stats <- bugs %>%
  group_by(error_loc) %>%
  summarize(n = n()) %>%
  mutate(error_loc = paste0("location_", str_to_lower(error_loc))) %>%
  rename(key = error_loc, value = n)
stats <- stats %>% bind_rows(location_stats)

formatted_bugs <- bugs %>%
  mutate(crate_name = ifelse(is.na(root_crate_name), crate_name, root_crate_name)) %>%
  mutate(version = ifelse(is.na(root_crate_version), version, root_crate_version)) %>%
  select(-root_crate_name, -root_crate_version) %>%
  mutate(bug_id = paste0("\\refstepcounter{bugcounter}\\label{", bug_id, "}\\ref{", bug_id, "}")) %>%
  mutate(
    issue = parse_links(issue, "issues", gh_id_parse_fn),
    pull_request = parse_links(pull_request, "pull", gh_id_parse_fn),
    commit = parse_links(commit, "commit", commit_hash_parse_fn),
  ) %>%
  mutate(annotated_error_type = ifelse(annotated_error_type == error_type, "-", annotated_error_type)) %>%
  select(bug_id, crate_name, version, error_type, annotated_error_type, error_loc, fix_loc, issue, pull_request, commit) %>%
  arrange(error_type, annotated_error_type, commit) %>%
  mutate(version = ifelse(version == "0.1.16+minimap2.2.26", "0.1.16\\tablefootnote{+minimap2.2.26}", version))

colnames(formatted_bugs) <- c("ID", "Crate", "Version", "Error Category", "Error Type", "Fix", "Error", "Issue(s)", "Pull Request(s)", "Commit(s)")

bold <- function(x) {
  paste("{\\textbf{", x, "}}", sep = "")
}

escape_underscore <- function(x) {
  str_replace_all(x, "_", "\\\\_")
}

print(
  xtable(formatted_bugs, type = "latex", align = "|c|l|c|l|l|l|l|c|c|c|c|"),
  file = file.path("./build/visuals/bug_table.tex"),
  sanitize.text.function = escape_underscore,
  sanitize.colnames.function = bold,
  hline.after = c(-1, rep(c(0:nrow(formatted_bugs)))),
  include.rownames = FALSE,
  floating = FALSE,
  comment = FALSE
)

bug_counts <- bugs %>%
  group_by(bug_category) %>%
  summarize(n = n()) %>%
  arrange(desc(n))

bug_counts_table <- bugs %>%
  group_by(bug_category, fix_loc, error_loc) %>%
  summarize(n = n()) %>%
  ungroup() %>%
  pivot_wider(names_from = bug_category, values_from = n) %>%
  mutate_all(replace_na, 0) %>%
  arrange(error_loc, fix_loc)

bug_counts_table <- bug_counts_table %>%
  bind_rows(bug_counts_table %>% select(-fix_loc, -error_loc) %>% summarise_all(sum)) %>%
  mutate(`Total` = rowSums(select(., -fix_loc, -error_loc))) %>%
  mutate_all(~ ifelse(. == 0, "", as.character(.))) %>%
  mutate(fix_loc = ifelse(is.na(fix_loc), "Total", fix_loc)) %>%
  write_csv(file.path("./build/visuals/bug_counts_table.csv"))

all <- read_csv(file.path("./dataset/population.csv"), show_col_types = FALSE)

popularity <- bugs %>%
  mutate(crate_name = ifelse(!is.na(root_crate_name), root_crate_name, crate_name)) %>%
  mutate(version = ifelse(!is.na(root_crate_version), root_crate_version, version)) %>%
  mutate(id = paste0("\\ref{", bug_id, "}")) %>%
  select(crate_name, version, id) %>%
  inner_join(all, by = c("crate_name", "version")) %>%
  select(
    crate_name,
    version,
    avg_daily_downloads,
    downloads,
    last_updated,
    id
  ) %>%
  mutate(avg_daily_downloads = as.integer(round(avg_daily_downloads, 0))) %>%
  mutate(last_updated = as.character(last_updated)) %>%
  mutate(days_since_last_update = as.numeric(difftime(as.Date("2023-09-20"), as.Date(last_updated), units = "weeks"))) %>%
  arrange(desc(avg_daily_downloads))

gt_ten_thousand <- popularity %>%
  filter(avg_daily_downloads > 10000) %>%
  nrow()

lt_hundred <- popularity %>%
  filter(avg_daily_downloads < 100) %>%
  nrow()

lt_ten <- popularity %>%
  filter(avg_daily_downloads < 10) %>%
  nrow()

yrs_since_update <- round(mean(popularity$days_since_last_update) / 365, 1)
stats <- stats %>% add_row(key = "daily_greater_than_10k", value = gt_ten_thousand)
stats <- stats %>% add_row(key = "daily_less_than_100", value = lt_hundred)
stats <- stats %>% add_row(key = "daily_less_than_10", value = lt_ten)

popularity_formatted <- popularity %>%
  select(crate_name, version, avg_daily_downloads, downloads, last_updated, id) %>%
  group_by(crate_name, version, avg_daily_downloads, downloads, last_updated) %>%
  summarize(ids = paste0(id, collapse = ", ")) %>%
  arrange(desc(downloads)) %>%
  mutate(avg_daily_downloads = format(avg_daily_downloads, big.mark = ",", scientific = FALSE)) %>%
  mutate(downloads = format(downloads, big.mark = ",", scientific = FALSE)) %>%
  ungroup()

colnames(popularity_formatted) <- c(
    "Crate", "Version", 
    "Mean {\\scriptsize\\faFileDownload}\\ /\\ Day",
     "{\\scriptsize\\faFileDownload} All-Time",
      "Last Updated", "Bug IDs"
)

print(
  xtable(popularity_formatted, type = "latex", align = "|l|l|c|r|r|c|c|"),
  file = file.path("./build/visuals/popularity_table.tex"),
  sanitize.text.function = escape_underscore,
  sanitize.colnames.function = bold,
  hline.after = c(-1, 0, rep(c(0:nrow(popularity_formatted)))),
  include.rownames = FALSE,
  floating = FALSE,
  comment = FALSE
)

bugs <- bugs %>%
  select(crate_name, version, test_name, error_type, annotated_error_type, issue, pull_request, commit) %>%
  filter(!is.na(pull_request) | !is.na(commit) | !is.na(issue))

bugs_fixed <- bugs %>%
  filter(!is.na(commit)) %>%
  nrow()

stats <- stats %>% add_row(key = "bugs_fixed", value = bugs_fixed)
bug_stats <- bugs %>%
  mutate(error_type = str_to_lower(error_type)) %>%
  mutate(error_type = str_replace_all(error_type, " ", "_")) %>%
  mutate(error_type = str_replace_all(error_type, "<T>::", "_")) %>%
  mutate(error_type = str_replace_all(error_type, "()", ""))

annotated_counts <- bugs %>%
  group_by(annotated_error_type) %>%
  summarize(n = n()) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{UnsafeCell<T>\\}", "unsafecell")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{\\\\&mut T\\}", "mut_ref")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{\\\\&T\\}", "ref")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{\\*mut T\\}", "mut_ptr")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{\\*const T\\}", "const_ptr")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{const\\}", "const")) %>%
  mutate(annotated_error_type = str_replace_all(annotated_error_type, "\\\\littlerust\\{\\\\&T as \\*mut T\\}", "const_ref_as_mut_ptr")) %>%
  mutate(key = paste0("annotated_", str_to_lower(str_replace_all(annotated_error_type, " ", "_"))), value = n) %>%
  select(key, value)

stats <- stats %>% bind_rows(annotated_counts)

bug_counts <- bug_stats %>%
  group_by(error_type) %>%
  summarize(n = n()) %>%
  mutate(error_type = paste0("error_count_", error_type)) %>%
  rename(key = error_type, value = n)

bug_crate_counts <- bug_stats %>%
  select(crate_name, error_type) %>%
  group_by(error_type) %>%
  summarize(n = n_distinct(crate_name)) %>%
  mutate(error_type = paste0("crate_count_", error_type)) %>%
  rename(key = error_type, value = n)

stats <- stats %>% bind_rows(bug_counts)
stats <- stats %>% bind_rows(bug_crate_counts)
stats <- stats %>% add_row(key = "num_bugs", value = nrow(bugs))
stats <- stats %>% add_row(key = "num_crates_with_bugs", value = n_distinct(bugs$crate_name))
stats %>% write_csv(stats_file)
