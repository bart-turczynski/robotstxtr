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
# not skipped, did not fail or error, and passed at least one expectation.
#
# A `locale_assertions` entry of .fleet-ci.yml: the fleet-ci local gate runs
# it after each locale leg's check (full tier), and CI's `t2-locale` after
# each of its legs, with FLEET_RCHECK_DIR naming the leg's .Rcheck
# directory, which holds the robotstxtr that check installed. The locales
# come from .fleet-ci.yml's `locales`. In the local gate, gate-run.R starts
# the command with R_PROFILE_USER set to the image's tooling Rprofile and
# R_LIBS set to the run library, so the library path is the leg's .Rcheck
# directory, then the tooling library, then the run library: testthat, and
# any robotstxtr dependency the tooling library holds, come from the tooling
# library, the rest from the run library (FLEET_RUN_LIB is unset there). In
# CI the run library is FLEET_RUN_LIB, and the command runs without the
# tooling library.
#
# Usage, from the package root:
#   Rscript scripts/check-locale-legs.R [<library holding robotstxtr>]
# The library defaults to FLEET_RCHECK_DIR.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) {
  stop("usage: check-locale-legs.R [<library holding robotstxtr>]",
    call. = FALSE
  )
}
lib <- if (length(args)) args[[1L]] else Sys.getenv("FLEET_RCHECK_DIR")
if (!nzchar(lib) || !dir.exists(file.path(lib, "robotstxtr"))) {
  stop("no robotstxtr installed in '", lib, "' (FLEET_RCHECK_DIR or the ",
    "argument)",
    call. = FALSE
  )
}
run_lib <- Sys.getenv("FLEET_RUN_LIB")
.libPaths(c(lib, if (dir.exists(run_lib)) run_lib, .libPaths()))

locales <- readLines("tests/testthat/fixtures/case-folding-locales.txt")
if (!length(locales)) {
  stop("case-folding-locales.txt lists no locales", call. = FALSE)
}
# The probe the former CI ran ahead of its checks: R switches LC_CTYPE to each
# locale by its exact name, the way the tests detect it, and each folds "I" to
# the dotless U+0131, the mapping the legs exist to survive. A locale built on
# the wrong charmap would let its legs pass having proved nothing.
old <- Sys.getlocale("LC_CTYPE")
for (l in locales) {
  active <- suppressWarnings(Sys.setlocale("LC_CTYPE", l))
  folds <- identical(tolower("I"), intToUtf8(0x131L))
  invisible(Sys.setlocale("LC_CTYPE", old))
  if (!identical(active, l)) {
    stop("R cannot switch LC_CTYPE to ", l, call. = FALSE)
  }
  if (!folds) {
    stop(l, " does not fold I to a dotless i; its legs would prove nothing",
      call. = FALSE
    )
  }
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
