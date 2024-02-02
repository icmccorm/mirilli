suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(stringr)
    library(ggsankey)
    library(ggplot2)
    library(tidyr)
    library(extrafont)
    library(extrafontdb)
    library(cowplot)
})
loadfonts(quiet = TRUE)

UNSUPPORTED_OP_EQUIVALENT <- c("Unsupported Operation", "LLI Internal Error")

errors <- read_csv(file.path("build/stage3/errors_unique.csv"))

calculate_location <- function(kind_stack, error_root_stack, error_root_tree) {
    ifelse(
        !is.na(kind_stack),
        ifelse(error_root_stack == error_root_tree, "Same", "Different"),
        "New"
    )
}

borrowing_errors_final <- errors %>%
    filter(error_type_stack == "Borrowing Violation" | error_type_tree == "Borrowing Violation") %>%
    filter(is.na(kind_stack) | (!is.na(kind_stack) & !is.na(kind_tree))) %>%
    select(kind_stack, exit_code_stack, error_root_stack, kind_tree, exit_code_tree, error_root_tree) %>%
    separate(kind_tree, into = c("kind_tree", "subkind_tree"), sep = "-") %>%
    mutate(tb_error_location = calculate_location(
        kind_stack,
        error_root_stack,
        error_root_tree
    )) %>%
    rename(`SB Error Type` = kind_stack, `TB Error Location` = tb_error_location, `TB Error Type` = kind_tree, `TB Error Subtype` = subkind_tree) %>%
    make_long(`SB Error Type`, `TB Error Type`, `TB Error Subtype`) %>%
    filter(!is.na(node))

dagg <- borrowing_errors_final %>%
    group_by(node) %>%
    tally()

borrowing_errors_merged <- merge(borrowing_errors_final, dagg, by.x = "node", by.y = "node", all.x = TRUE)

pl <- ggplot(borrowing_errors_merged, aes(
    x = x,
    next_x = next_x,
    node = node,
    next_node = next_node,
    fill = factor(node),
)) +
    geom_sankey(
        flow.alpha = 0.5, # This Creates the transparency of your node
        node.color = "black", # This is your node color
        show.legend = FALSE,
        space = 10
    ) +
    geom_sankey_label(
        aes(
            group = node, label = paste0(node, " (", n, ")"),
        ),
        fill = "white",
        alpha = 1,
        color = "black",
        hjust = 0,
        position = position_nudge(x = 0.075),
        family = "Linux Libertine Display",
        size = 3
    )
# hide axis labels
pl <- pl +
    coord_cartesian(clip = "off") +
    theme(
        axis.text.x = element_text(family = "Linux Libertine Display", color = "black"),
        axis.text.y = element_blank(),
        axis.ticks.y = element_blank(),
        axis.title.x = element_blank(),
        axis.title.y = element_blank(),
        panel.background = element_blank()
    )


save_plot(file.path("./build/visuals/borrow_sankey.pdf"), pl, base_width = 6.65, base_height = 2, units = "in", dpi = 300)
