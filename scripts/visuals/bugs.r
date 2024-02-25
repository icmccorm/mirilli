suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(stringr)
    library(tidyr)
    library(xtable)
    library(ggplot2)
    library(ggrepel)
})
options(dplyr.summarise.inform = FALSE)

as_link <- function(link_text, url) {
    return(paste0("\\href{", url, "}{", link_text, "}"))
}

parse_links <- function(links, item_text, parse_fn) {
    links %>%
        sapply(function(issue_text) {
            str_split(issue_text, ",") %>%
                sapply(function(x) {
                    parse_fn(x, item_text)
                }) %>%
                sapply(paste0)
        })
}

gh_id_parse_fn <- function(link, item_text) {
    if (!is.na(link) & grepl(paste0(item_text, "/[0-9]+$"), link)) {
        issue_number <- str_extract(link, "[0-9]+$")
        as_link(paste0("\\#", issue_number), link)
    } else {
        ""
    }
}
commit_hash_parse_fn <- function(link, item_text) {
    if (!is.na(link) & grepl(paste0(item_text, "/[0-9a-fA-F]+$"), link)) {
        issue_number <- str_extract(link, "[0-9a-fA-F]+$")
        # get the first 7 characters of the commit hash
        as_link(substr(issue_number, 1, 7), link)
    } else {
        ""
    }
}

bugs <- read_csv(file.path("./build/stage3/bugs.csv"), show_col_types = FALSE)

formatted_bugs <- bugs %>%
    select(-root_crate_name, -root_crate_version) %>%
    mutate(id = paste0("\\#", row_number())) %>%
    mutate(
        issue = parse_links(issue, "issues", gh_id_parse_fn),
        pull_request = parse_links(pull_request, "pull", gh_id_parse_fn),
        commit = parse_links(commit, "commit", commit_hash_parse_fn)
    )
colnames(formatted_bugs) <- c("ID", "Crate", "Version", "Test", "Error Type", "Issue(s)", "Pull Request(s)", "Commit(s)")
bold <- function(x) {
    paste("{\\textbf{", x, "}}", sep = "")
}
escape_underscore <- function(x) {
    str_replace_all(x, "_", "\\\\_")
}
print(
    xtable(formatted_bugs, type = "latex", align = "|c|l|c|l|l|l|c|c|c|"),
    file = file.path("./build/visuals/bug_table.tex"),
    sanitize.text.function = escape_underscore,
    sanitize.colnames.function = bold,
    hline.after = c(-1, rep(c(0:nrow(formatted_bugs)))),
    include.rownames = FALSE,
    floating = FALSE,
    comment = FALSE
)

# create a pie chart of the bugs
bug_counts <- bugs %>%
    group_by(error_type) %>%
    summarize(n = n()) %>%
    arrange(desc(n))


bug_counts_plot <- ggplot(data=bug_counts, aes(x=0.5, y=n)) +
  coord_polar("y", start = 0) +
  theme_void(base_size = 10) +
  xlim(c(-1, 1)) +
  geom_bar(aes(fill = reorder(error_type, n)), stat="identity") +
  theme(legend.position = "right", text = element_text(family = "Linux Libertine Display", color = "black"), title = element_blank()) +
  geom_label(data=subset(bug_counts, n>1), aes(x=0.5, label = n, family = "Linux Libertine Display", group = reorder(error_type, n)),colour = "black", position= position_stack(vjust=0.5)) 

ggsave(file.path("./build/visuals/bugs.pdf"), plot = bug_counts_plot, width = 4, height = 1.8, dpi = 300)


all <- read_csv(file.path("./results/all.csv"), show_col_types = FALSE, col_names = c("crate_name", "version", "last_updated", "downloads", "percentile_downloads", "avg_daily_downloads", "percentile_daily_download")) %>%
select(crate_name, version)

popularity <- bugs %>%
    mutate(crate_name = ifelse(!is.na(root_crate_name), root_crate_name, crate_name)) %>%
    mutate(version = ifelse(!is.na(root_crate_version), root_crate_version, version)) %>%
    select(crate_name, version, id) %>%
    inner_join(all, by = c("crate_name", "version")) %>%
    mutate(days_since_last_update = as.numeric(difftime(as.Date("2023-09-20"), as.Date(last_updated), units = "weeks"))) %>%
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
    arrange(desc(avg_daily_downloads))


popularity_formatted <- popularity %>%
    mutate(daily = format(avg_daily_downloads, big.mark = ",", scientific = FALSE)) %>%
    mutate(all_time = format(downloads, big.mark = ",", scientific = FALSE)) %>%
    select(crate_name, version, daily, all_time, last_updated, id) %>%
    group_by(crate_name, version, daily, all_time, last_updated) %>%
    mutate(id = paste0("\\#", id)) %>%
    summarize(bug_ids = paste0(id, collapse = ", ")) %>%
    ungroup()

colnames(popularity_formatted) <- c("Crate", "Version", "Mean {\\scriptsize\\faFileDownload}\\ /\\ Day", "{\\scriptsize\\faFileDownload} All-Time", "Last Updated", "Bug IDs")
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
