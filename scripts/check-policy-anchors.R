#!/usr/bin/env Rscript
# check-policy-anchors v1
#
# Every `design/engine-profiles.md#x` string in R/*.R must name an anchor that
# the document defines as `<a id="x"></a>`. The v1 engine returns these strings
# as `policy_source`, which callers keep, so a renamed heading or a dropped
# anchor would leave each result that names it pointing at nothing
# (ROBO-njliiuhz). The headings slug to other names, so the anchors are
# explicit in the document.
#
#   Rscript scripts/check-policy-anchors.R [root]   # root defaults to "."
#
# A cheap gate of the fleet-ci local gate (.fleet-ci.yml). Base R only. Exit 1
# on any dangling reference, naming it by file and line, and on finding no
# reference at all, which would let the check pass vacuously. The optional root
# points the check at a copy of the tree, for the red cases.

doc_rel <- file.path("design", "engine-profiles.md")
ref_pattern <- "design/engine-profiles[.]md#[A-Za-z0-9_-]+"
tag_pattern <- "<a[[:space:]]+id=\"[^\"]+\""

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1L]] else "."
doc <- file.path(root, doc_rel)
r_dir <- file.path(root, "R")
r_files <- sort(list.files(r_dir, pattern = "[.]R$", full.names = TRUE))

if (!file.exists(doc)) {
  cat("check-policy-anchors: ", doc, " is missing\n", sep = "")
  quit(status = 1L)
}
if (!length(r_files)) {
  cat("check-policy-anchors: no R/*.R files under ", r_dir, "\n", sep = "")
  quit(status = 1L)
}

# The anchor ids the document defines.
doc_text <- paste(readLines(doc, warn = FALSE), collapse = "\n")
tags <- regmatches(
  doc_text, gregexpr(tag_pattern, doc_text, useBytes = TRUE)
)[[1L]]
defined <- sub("\"$", "", sub("^<a[[:space:]]+id=\"", "", tags))

# Every reference in R/*.R, with its file and line.
refs <- do.call(rbind, lapply(r_files, function(path) {
  lines <- readLines(path, warn = FALSE)
  hits <- regmatches(lines, gregexpr(ref_pattern, lines, useBytes = TRUE))
  data.frame(
    where = sprintf(
      "%s:%d", file.path("R", basename(path)),
      rep(seq_along(lines), lengths(hits))
    ),
    anchor = sub("^.*#", "", unlist(hits)),
    stringsAsFactors = FALSE
  )
}))

if (!nrow(refs)) {
  cat(paste0(
    "check-policy-anchors: no design/engine-profiles.md#x reference in R/*.R; ",
    "the check would pass vacuously\n"
  ))
  quit(status = 1L)
}

dangling <- !refs$anchor %in% defined
if (any(dangling)) {
  cat(sprintf(
    paste0(
      "check-policy-anchors: %s names design/engine-profiles.md#%s, ",
      "which %s does not define as <a id=\"%s\"></a>\n"
    ),
    refs$where[dangling], refs$anchor[dangling], doc_rel,
    refs$anchor[dangling]
  ), sep = "")
  cat("Add the anchor to its heading or bullet, or fix the reference.\n")
  quit(status = 1L)
}
cat(sprintf(
  "check-policy-anchors: %d references in R/ resolve to anchors in %s\n",
  nrow(refs), doc_rel
))
