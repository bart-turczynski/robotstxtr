# Google fidelity differential (ROBO-deehqhlc). Dev only: never run by tests.
#
# Feeds the synthesized fixtures of
# tests/testthat/fixtures/google-fidelity-deehqhlc/cases.R to a reference
# binary built from the pristine upstream google/robotstxt (pinned SHA
# 22b355ff855419e6a3ff8ff09c0ad7fdb17116f9; the maintainer-only harness of
# robotstxt-cpp, PRD §7 slice C5) and to each robotstxtr Google path, then
# compares the decision and the matched line.
#
# Usage:
#   Rscript dev/google-fidelity/differential.R <google_ref binary> [out_dir]
#
# The binary reads a manifest of TAB-separated `<body_file> <agent> <url>`
# lines and writes `<allowed 0|1> <matching_line> <ever_seen 0|1>` per line.
# `ever_seen` (the matcher's ever_seen_specific_agent()) is not read:
# robotstxtr exposes no equivalent on any path, so there is nothing to
# compare it with. `out_dir` (default: a fresh temporary directory) receives
# the bodies, the manifest, the reference output and `differences.tsv`.
#
# Exit status 1 when the reference's live answers drift from the answers
# recorded in cases.R (the pinned tests would then state the wrong
# reference), or when a row differs from the reference in a way
# gf_expected_difference() in cases.R does not list (a difference outside the
# classes of design/engine-profiles.md §5b); 0 otherwise.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop("usage: differential.R <google_ref binary> [out_dir]", call. = FALSE)
}
binary <- normalizePath(args[[1L]], mustWork = TRUE)
out_dir <- if (length(args) >= 2L) args[[2L]] else tempfile("google-fidelity-")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_dir <- normalizePath(out_dir, mustWork = TRUE)

script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
root <- normalizePath(file.path(dirname(script), "..", ".."), mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE, export_all = FALSE)

env <- new.env(parent = asNamespace("robotstxtr"))
sys.source(
  file.path(root, "tests", "testthat", "helper-fake-ssrfr.R"), envir = env
)
sys.source(
  file.path(
    root, "tests", "testthat", "fixtures", "google-fidelity-deehqhlc",
    "cases.R"
  ),
  envir = env
)
cases <- env$gf_cases()

# --- The reference ------------------------------------------------------------

manifest <- character(length(cases))
for (k in seq_along(cases)) {
  case <- cases[[k]]
  body_file <- file.path(out_dir, sprintf("body-%03d.bin", k))
  writeBin(case$body, body_file)
  manifest[[k]] <- paste(body_file, case$token, case$url, sep = "\t")
}
manifest_file <- file.path(out_dir, "manifest.tsv")
ref_file <- file.path(out_dir, "reference.tsv")
con <- file(manifest_file, open = "wb")
writeLines(enc2utf8(manifest), con, sep = "\n", useBytes = TRUE)
close(con)
# system2() quotes `command` itself; `args` go to the shell as given.
status <- system2(binary, shQuote(c(manifest_file, ref_file)))
if (!identical(status, 0L)) {
  stop("the reference binary failed with status ", status, call. = FALSE)
}
# The third column, ever_seen, is skipped (see the header).
ref <- utils::read.delim(
  ref_file, header = FALSE, col.names = c("allowed", "line", "ever_seen"),
  colClasses = c("integer", "integer", "NULL")
)
stopifnot(nrow(ref) == length(cases))

drift <- character()
for (k in seq_along(cases)) {
  case <- cases[[k]]
  if (!identical(case$ref_allowed, ref$allowed[[k]] == 1L) ||
        !identical(case$ref_line, ref$line[[k]])) {
    drift <- c(drift, sprintf(
      "%s: recorded %s/%d, reference %d/%d", case$id,
      case$ref_allowed, case$ref_line, ref$allowed[[k]], ref$line[[k]]
    ))
  }
}

# --- robotstxtr, and the comparison -------------------------------------------

rows <- lapply(seq_along(cases), function(k) {
  ours <- env$gf_run_case(cases[[k]])
  ours$family <- cases[[k]]$family
  ours$ref_allowed <- ref$allowed[[k]] == 1L
  ours$ref_line <- ref$line[[k]]
  ours
})
all <- do.call(rbind, rows)
our_line <- ifelse(is.na(all$line), 0L, all$line)
all$decision_differs <- is.na(all$allowed) | all$allowed != all$ref_allowed
all$line_differs <- !all$decision_differs & our_line != all$ref_line
all$class <- vapply(seq_len(nrow(all)), function(k) {
  want <- env$gf_expected_difference(all$id[[k]], all$path[[k]])
  if (is.null(want)) NA_integer_ else want$class
}, integer(1L))
differs <- all$decision_differs | all$line_differs
diff <- all[differs, c(
  "id", "family", "path", "class", "ref_allowed", "ref_line", "allowed",
  "line", "reason", "decision_differs", "line_differs"
)]
utils::write.table(
  diff, file.path(out_dir, "differences.tsv"),
  sep = "\t", quote = FALSE, row.names = FALSE
)
unexpected <- diff[is.na(diff$class), , drop = FALSE]

cat(sprintf(
  paste0(
    "cases: %d; robotstxtr rows: %d; differing rows: %d ",
    "(decision %d, line only %d; unexpected %d)\n"
  ),
  length(cases), nrow(all), nrow(diff), sum(all$decision_differs),
  sum(all$line_differs), nrow(unexpected)
))
if (nrow(diff) > 0L) {
  print(diff[c("id", "path", "class", "ref_allowed", "ref_line", "allowed",
               "line", "reason")], row.names = FALSE)
}
cat("output in", out_dir, "\n")
failed <- FALSE
if (length(drift) > 0L) {
  cat("recorded reference answers drifted:\n", paste0("  ", drift, "\n"))
  failed <- TRUE
}
if (nrow(unexpected) > 0L) {
  cat(
    "rows differing outside the expected classes:\n",
    paste0("  ", unexpected$id, " ", unexpected$path, "\n")
  )
  failed <- TRUE
}
if (failed) {
  quit(status = 1L)
}
