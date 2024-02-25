suppressPackageStartupMessages({
    library(dplyr)
    library(readr)
    library(ggplot2)
    library(extrafont)
    library(extrafontdb)
})
loadfonts(quiet = TRUE)

if (dir.exists("./build/visuals")) {
    unlink("./build/visuals", recursive = TRUE)
}
dir.create("./build/visuals")

source("./scripts/visuals/bugs.r")

# a sankey diagram of test cases passing through stages 2 and 3
# this should segment errors into results, e.g. different flows
# for failures, invalid uses of uninit bytes, and then errors to investigate.
# this should also demonstrate deduplication, how can we compress these errors?

# a sankey chart of stacked borrows errors flowing into tree borrows errors.

# a pie chart of each of the ~50 actual errors and their causes.

# two tables describing the different statistics reported at runtime between for
# tests that engaged the interpreter.

# A diagram ranking downloads in the past 6 months to downloads over all time for
