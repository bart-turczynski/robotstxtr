#!/usr/bin/env Rscript
# Positive proof that the case-folding locale legs of
# test-ascii-case-folding-tldlaxgq.R ran (ported from pslr's script).
#
# The test file runs two legs per locale listed in
# tests/testthat/fixtures/case-folding-locales.txt, and a leg skips on a
# machine that lacks its locale. A skip is a pass as far as R CMD check is
# concerned, so a CI image that silently lost a locale would go green while
# testing nothing. Checking that no skip message appears is not enough either:
# it also passes when the legs never ran at all.
#
# So this script runs the test file against an installed robotstxtr and
# demands, for every locale in the list, a test of each expected name that was
# not skipped, did not fail or error, and passed at least one expectation. The
# CI jobs that build the locales run it after R CMD check, against the package
# the check installed.
#
# Usage, from the package root:
#   Rscript scripts/check-locale-legs.R <library holding robotstxtr>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("usage: check-locale-legs.R <library holding robotstxtr>", call. = FALSE)
}
.libPaths(c(args[[1L]], .libPaths()))

locales <- readLines("tests/testthat/fixtures/case-folding-locales.txt")
if (!length(locales)) {
  stop("case-folding-locales.txt lists no locales", call. = FALSE)
}
results <- as.data.frame(testthat::test_file(
  "tests/testthat/test-ascii-case-folding-tldlaxgq.R",
  package = "robotstxtr",
  load_package = "installed",
  reporter = "silent",
  stop_on_failure = FALSE
))

prefixes <- c(
  "ascii_lower() maps A-Z only under ",
  "ASCII tokens match the same under "
)
expected <- as.vector(outer(prefixes, locales, paste0))
legs <- results[results$test %in% expected, , drop = FALSE]
missing <- setdiff(expected, legs$test)
bad <- legs[
  legs$skipped | legs$error | legs$failed > 0L | legs$passed < 1L,
  ,
  drop = FALSE
]
if (length(missing) || nrow(bad)) {
  if (length(missing)) {
    message("Locale legs that did not run: ", toString(missing))
  }
  if (nrow(bad)) {
    message(
      "Locale legs that skipped, failed or proved nothing: ",
      toString(bad$test)
    )
  }
  stop("the case-folding locale legs did not all run and pass", call. = FALSE)
}
cat(sprintf(
  "Locale legs ran and passed (%d expectations): %s\n",
  sum(legs$passed),
  toString(locales)
))
