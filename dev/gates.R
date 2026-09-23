#!/usr/bin/env Rscript
#
# Folded CI "gates" job (SEOR-pgammbgo).
#
# WHY THIS EXISTS. robotstxtr measured as one of the three worst repos in the
# fleet's CI survey: ~10 jobs, ~7.5 minutes of actual compute, against a very
# large wall time driven by ~2 minutes of pure runner-pickup tax PER JOB. Five
# `stage: verify` jobs -- lint, readme, docs, vendor-fidelity:yandex,
# vendor-fidelity:bing -- measured on a real main pipeline (#2875793448) at
# 35.9s + 43.1s + 37.0s + 4.4s + 8.3s = ~128.7s of combined compute, i.e. each
# one is genuinely cheap; five separate runner pickups to run ~2m9s of work is
# the actual waste. Folding them into one job removes four pickups and keeps
# the compute unchanged.
#
# vendor-fidelity:yandex and vendor-fidelity:bing were the judgment call: the
# name suggests they validate against a live vendor spec, which would make
# folding them a flakiness risk (a vendor outage would redden the whole fast
# gate). Read, they are NOT network calls -- both are base-R/jsonlite
# comparisons of the REAL vendored source tree under src/vendor/* against a
# frozen MANIFEST.dcf checked into inst/vendor/*; grepping both scripts and
# their R/ helpers (vendor-manifest-verify.R, bing-corpus.R) for
# http(s)://, download.file, httr::, curl:: turns up exactly one hit: a
# hardcoded "https://example.test" placeholder string used only as an
# in-process argument to robots_evaluate_text_v1(), never fetched. So they
# fold in safely.
#
# citation-version does NOT fold in here, on purpose, and stays its own
# .gitlab-ci.yml job on `image: python:3.13-alpine`. Folding is folding
# IMAGES, not just commands: the five gates above all ran (and still run)
# on no `image:` override, i.e. the pipeline's `rocker/r-ver:4.6.1` default,
# so combining them changes nothing about what interpreter each command runs
# under. citation-version is the one job that overrode the image, and for a
# real reason -- verified directly against the exact pinned tag:
#   docker run --rm rocker/r-ver:4.6.1 sh -c 'which python3 || echo "NO python3"'
#   -> NO python3
# `apt-get install -y --no-install-recommends python3` inside that image DOES
# work (also verified, with check-citation's own self-test and main check
# both passing under it), so folding it in was an option, not a blocker --
# declined anyway, because check-citation.py is stdlib-only and offline BY
# DESIGN (that is exactly why it was given its own minimal image rather than
# the R toolchain's), and paying an apt-get on the R gates image on every
# merge, forever, to save one more runner pickup is a worse trade than
# leaving the cheapest of the six original jobs (5.1s) on the image built
# for it. See .gitlab-ci.yml's `gates` job comment for the full reasoning.
#
# THE SHAPE, ported from rurl's tools/verify.R (RURL-mvsxmyww): every gate
# below runs to completion regardless of an earlier one failing, every exit
# status is captured, and ONE final summary names every gate's verdict before
# a single nonzero exit. This is NOT fail-fast -- a harness that stopped at
# the first red gate would gut the point of folding: you would trade several
# separate red/green signals for one, and still have to re-run to find the
# second failure. dev/verify.sh (the local pre-push gate) was checked first
# and does NOT have this property (`set -euo pipefail`, so it stops at its
# first failing command); it also does a different job (lint + docs-drift +
# a full `R CMD check --as-cran` on a git-archive export) and is intentionally
# left alone here rather than repurposed. This script is a second, narrower
# harness for exactly the five folded verify-stage gates.
#
# BEFORE/AFTER command enumeration (also in the commit message):
#   lint                      Rscript -e 'lintr::lint_package()'
#   readme                    Rscript -e 'devtools::build_readme()'
#                              + `git diff --exit-code -- README.md`
#   docs                      Rscript dev/check-docs-drift.R
#   vendor-fidelity:yandex    Rscript dev/verify-yandex-vendor.R
#   vendor-fidelity:bing      Rscript dev/verify-bing-vendor.R
# Every one of those commands is still run, verbatim, below -- none dropped,
# none reordered in a way that changes what runs. citation-version's two
# commands (python3 scripts/check-citation.py --self-test, then without
# --self-test) are UNCHANGED in .gitlab-ci.yml's separate citation-version
# job -- not moved here.
#
# Usage (from the package root): Rscript dev/gates.R

if (!file.exists("DESCRIPTION") || !file.exists(".git")) {
  stop("run this from the repository root", call. = FALSE)
}

results <- list()

run_step <- function(label, command, args = character(0), env = character(0)) {
  log <- tempfile(fileext = ".log")
  t0 <- Sys.time()
  # system2() shell-quotes `command` but NOT `args`, so an argument containing
  # shell metacharacters (e.g. the parentheses in an -e expression) must be
  # quoted here or the underlying shell mis-parses it.
  status <- suppressWarnings(system2(command, vapply(args, shQuote, character(1)),
                                     stdout = log, stderr = log, env = env))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  ok <- identical(as.integer(status), 0L)
  cat(sprintf("[gates] %-4s %-32s %6.1fs\n", if (ok) "PASS" else "FAIL",
              label, secs))
  out <- tryCatch(readLines(log, warn = FALSE), error = function(e) character())
  if (!ok) {
    cat(paste0("        | ", utils::tail(out, 40L), collapse = "\n"), "\n",
        sep = "")
  }
  results[[length(results) + 1L]] <<- list(label = label, ok = ok)
  invisible(ok)
}

cat("robotstxtr gates --", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("5 gate(s): lint, readme, docs,",
    "vendor-fidelity:yandex, vendor-fidelity:bing\n",
    "(citation-version runs as its own CI job, on its own image -- not here)\n\n")

# ---- lint --------------------------------------------------------------
# Verbatim `lint` job script. LINTR_ERROR_ON_LINT is a repo-wide CI variable
# (see .gitlab-ci.yml `variables:`), so lintr itself turns any lint into a
# nonzero exit; nothing extra to check here.
run_step("lint", "Rscript", c("-e", "lintr::lint_package()"))

# ---- readme --------------------------------------------------------------
# Verbatim `readme` job script, as two sub-commands: build then diff-check.
run_step("readme: build", "Rscript", c("-e", "devtools::build_readme()"))
run_step(
  "readme: README.md in sync",
  "git", c("diff", "--exit-code", "--", "README.md")
)

# ---- docs --------------------------------------------------------------
# Verbatim `docs` job script.
run_step("docs", "Rscript", "dev/check-docs-drift.R")

# ---- vendor-fidelity:yandex ----------------------------------------------
# Verbatim `vendor-fidelity:yandex` job script.
run_step("vendor-fidelity:yandex", "Rscript", "dev/verify-yandex-vendor.R")

# ---- vendor-fidelity:bing -------------------------------------------------
# Verbatim `vendor-fidelity:bing` job script.
run_step("vendor-fidelity:bing", "Rscript", "dev/verify-bing-vendor.R")

# ---- verdict --------------------------------------------------------------
cat("\n")
failed <- Filter(function(r) !r$ok, results)
cat(sprintf("%d step(s), %d failed\n", length(results), length(failed)))
if (length(failed)) {
  cat("VERDICT: FAIL --",
      paste(vapply(failed, function(r) r$label, character(1)),
            collapse = ", "), "\n")
  quit(status = 1)
}
cat("VERDICT: PASS -- all gates green\n")
