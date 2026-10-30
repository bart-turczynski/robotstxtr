#!/usr/bin/env Rscript
# check-news-version v1
#
# The top NEWS.md heading names the DESCRIPTION Version, or, while Version is
# a .9000 development version, "(development version)". A release bump that
# forgets the NEWS heading fails instead of reaching CRAN as "(development
# version)".
#
#   Rscript scripts/check-news-version.R      # from the package root
#
# A cheap gate of the fleet-ci local gate (.fleet-ci.yml), run in the full
# tier. It was the `news-version` gate of the former dev/gates.R
# (ROBO-srowxxtg), which the `gates` CI job and the old pre-push hook ran;
# the rule is unchanged. Base R only. Exit 1, naming both values, when they
# disagree.

version <- read.dcf("DESCRIPTION", fields = "Version")[[1L]]
parts <- strsplit(version, ".", fixed = TRUE)[[1L]]
is_dev <- length(parts) == 4L && as.integer(parts[4L]) >= 9000L
allowed <- if (is_dev) c("(development version)", version) else version

news <- readLines("NEWS.md", warn = FALSE, encoding = "UTF-8")
top <- grep("^# ", news, value = TRUE)[1L]
heading <- sub("^#\\s+robotstxtr\\s+", "", top)
cat("DESCRIPTION Version: '", version, "'\n", sep = "")
cat("Top NEWS heading:    '", top, "'\n", sep = "")
if (is.na(heading) || !heading %in% allowed) {
  cat(
    "With DESCRIPTION Version '", version, "' the top NEWS.md heading must be ",
    paste0("'# robotstxtr ", allowed, "'", collapse = " or "),
    ". Update NEWS.md.\n",
    sep = ""
  )
  quit(status = 1L)
}
cat("news-version: PASS\n")
