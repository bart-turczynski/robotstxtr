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
#   docs                      Rscript scripts/check-docs-drift.R
#   vendor-fidelity:yandex    Rscript dev/verify-yandex-vendor.R
#   vendor-fidelity:bing      Rscript dev/verify-bing-vendor.R
# Every one of those commands is still run, verbatim, below -- none dropped,
# none reordered in a way that changes what runs. citation-version's two
# commands (python3 scripts/check-citation.py --self-test, then without
# --self-test) are UNCHANGED in .gitlab-ci.yml's separate citation-version
# job -- not moved here.
#
# Usage (from the package root): Rscript dev/gates.R [gate ...]
#
# With no arguments all eight gates run: the five above plus news-version,
# codemeta and spelling, which came later (see their sections below).

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

record <- function(label, ok, detail = character()) {
  cat(sprintf("[gates] %-4s %-32s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok && length(detail)) {
    cat(paste0("        | ", detail, collapse = "\n"), "\n", sep = "")
  }
  results[[length(results) + 1L]] <<- list(label = label, ok = ok)
  invisible(ok)
}

# ---- lint --------------------------------------------------------------
# Verbatim `lint` job script. LINTR_ERROR_ON_LINT is a repo-wide CI variable
# (see .gitlab-ci.yml `variables:`), so lintr itself turns any lint into a
# nonzero exit; nothing extra to check here.
gate_lint <- function() {
  run_step("lint", "Rscript", c("-e", "lintr::lint_package()"))
}

# ---- readme --------------------------------------------------------------
# Verbatim `readme` job script, as two sub-commands: build then diff-check.
gate_readme <- function() {
  run_step("readme: build", "Rscript", c("-e", "devtools::build_readme()"))
  run_step(
    "readme: README.md in sync",
    "git", c("diff", "--exit-code", "--", "README.md")
  )
}

# ---- docs --------------------------------------------------------------
# Verbatim `docs` job script.
gate_docs <- function() {
  run_step("docs", "Rscript", "scripts/check-docs-drift.R")
}

# ---- vendor-fidelity:yandex ----------------------------------------------
# Verbatim `vendor-fidelity:yandex` job script.
gate_vendor_yandex <- function() {
  run_step("vendor-fidelity:yandex", "Rscript", "dev/verify-yandex-vendor.R")
}

# ---- vendor-fidelity:bing -------------------------------------------------
# Verbatim `vendor-fidelity:bing` job script.
gate_vendor_bing <- function() {
  run_step("vendor-fidelity:bing", "Rscript", "dev/verify-bing-vendor.R")
}

# ---- news-version and codemeta (ROBO-srowxxtg) -----------------------------
# These two replace the news-version.yaml and codemeta.yaml GitHub workflows
# that M1 (ROBO-tkmclvsg) deleted without a port. Ported from pagerankr's
# scripts/gates.R, with two changes:
#
# * news-version is stricter. pagerankr accepts "(development version)" under
#   any DESCRIPTION Version; here it passes only while Version is a .9000
#   development version, so a release bump that forgets the NEWS heading fails
#   instead of reaching CRAN as "(development version)".
# * codemeta also compares every dependency constraint with DESCRIPTION.
#   codemeta.json is hand-edited and never regenerated: codemetar would put
#   back the /-/issues tracker that the file deliberately replaces with
#   /-/work_items (ROBO-zghpvlxu). So nothing else keeps its requirement list
#   in step. That is also why the old codemeta.yaml, which regenerated the
#   file, is not carried. pagerankr's check for a `host::repo` spec mangled
#   into a URL is dropped: that damage comes from `Remotes:`, which this
#   package has none of.
#
# Both run in-process on base R plus jsonlite, which takes a second, so the
# pre-push hook runs them as well (`Rscript dev/gates.R news-version
# codemeta`). On a branch that hook is the only gate (SEOR-bmgkzhvy).

description_field <- function(field) {
  unname(read.dcf("DESCRIPTION", fields = field)[1L, 1L])
}

is_dev_version <- function(version) {
  parts <- strsplit(version, ".", fixed = TRUE)[[1L]]
  length(parts) == 4L && as.integer(parts[4L]) >= 9000L
}

gate_news_version <- function() {
  version <- description_field("Version")
  news <- readLines("NEWS.md", warn = FALSE)
  heading_line <- grep("^# ", news, value = TRUE)[1L]
  heading <- sub("^#\\s+robotstxtr\\s+", "", heading_line)
  allowed <- if (is_dev_version(version)) {
    c("(development version)", version)
  } else {
    version
  }
  ok <- !is.na(heading) && heading %in% allowed
  record("news-version", ok, sprintf(
    "top NEWS.md heading is '%s'; with DESCRIPTION Version '%s' it must be %s.",
    heading_line, version,
    paste0("'# robotstxtr ", allowed, "'", collapse = " or ")
  ))
}

# Named vector package -> constraint (NA when unconstrained).
description_deps <- function(fields) {
  values <- stats::na.omit(vapply(fields, description_field, character(1)))
  items <- trimws(unlist(strsplit(values, ",", fixed = TRUE)))
  items <- items[nzchar(items)]
  constraint <- ifelse(
    grepl("(", items, fixed = TRUE),
    gsub("\\s+", " ", trimws(sub("^[^(]*\\(([^)]*)\\).*$", "\\1", items))),
    NA_character_
  )
  stats::setNames(constraint, trimws(sub("\\(.*$", "", items)))
}

codemeta_deps <- function(entries) {
  # softwareRequirements also carries a plain "SystemRequirements" string.
  entries <- Filter(is.list, entries)
  constraint <- vapply(entries, function(d) {
    if (is.null(d$version)) NA_character_ else d$version
  }, character(1))
  ids <- vapply(entries, function(d) d$identifier, character(1))
  stats::setNames(constraint, ids)
}

dependency_drift <- function(what, declared, recorded) {
  drift <- character()
  for (pkg in sort(union(names(declared), names(recorded)))) {
    d <- if (pkg %in% names(declared)) declared[[pkg]] else "(absent)"
    r <- if (pkg %in% names(recorded)) recorded[[pkg]] else "(absent)"
    if (!identical(d, r)) {
      drift <- c(drift, sprintf(
        "%s %s: DESCRIPTION '%s', codemeta.json '%s'",
        what, pkg, if (is.na(d)) "(any)" else d, if (is.na(r)) "(any)" else r
      ))
    }
  }
  drift
}

gate_codemeta <- function() {
  version <- description_field("Version")
  meta <- jsonlite::read_json("codemeta.json", simplifyVector = FALSE)
  detail <- character()
  if (!identical(meta$version, version)) {
    detail <- sprintf("version: DESCRIPTION '%s', codemeta.json '%s'",
                      version, format(meta$version))
  }
  detail <- c(
    detail,
    dependency_drift("requirement",
                     description_deps(c("Depends", "Imports")),
                     codemeta_deps(meta$softwareRequirements)),
    dependency_drift("suggestion",
                     description_deps("Suggests"),
                     codemeta_deps(meta$softwareSuggestions))
  )
  if (length(detail)) {
    detail <- c(detail, paste(
      "Hand-edit codemeta.json to match. Do NOT run",
      "codemetar::write_codemeta(): it would revert issueTracker to /-/issues",
      "(ROBO-zghpvlxu)."
    ))
  }
  record("codemeta", !length(detail), detail)
}

# ---- spelling ---------------------------------------------------------------
# spelling::spell_check_package() over DESCRIPTION, man/, vignettes, README and
# NEWS, against `Language: en-US` and inst/WORDLIST. Nothing checked spelling
# here before 0.3.0, and win-builder found DESCRIPTION words the local check
# never reported: R CMD check needs an English aspell/hunspell dictionary and
# silently skips the check without one. CRAN ignores inst/WORDLIST, so a word
# listed here can still appear in the incoming NOTE; the list only stops new
# typos. Ported in spirit from pagerankr's lint gate, as its own gate.
gate_spelling <- function() {
  bad <- spelling::spell_check_package()
  detail <- character()
  if (nrow(bad)) {
    detail <- c(
      sprintf("%s: %s", bad$word,
              vapply(bad$found, toString, character(1))),
      paste("Correct the prose, or add genuine terms to inst/WORDLIST",
            "(spelling::update_wordlist())."))
  }
  record("spelling", !nrow(bad), detail)
}

available <- list(
  "lint" = gate_lint,
  "readme" = gate_readme,
  "docs" = gate_docs,
  "vendor-fidelity:yandex" = gate_vendor_yandex,
  "vendor-fidelity:bing" = gate_vendor_bing,
  "news-version" = gate_news_version,
  "codemeta" = gate_codemeta,
  "spelling" = gate_spelling
)

# With no arguments every gate runs, which is what the CI job does. Named gates
# run just that subset, still to completion, never fail-fast.
selected <- commandArgs(trailingOnly = TRUE)
if (!length(selected)) {
  selected <- names(available)
}
unknown <- setdiff(selected, names(available))
if (length(unknown)) {
  cat("[gates] unknown gate(s):", toString(unknown), "\n")
  cat("[gates] available:", toString(names(available)), "\n")
  quit(status = 2L)
}

cat("robotstxtr gates --", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat(length(selected), "gate(s):", toString(selected), "\n",
    "(citation-version runs as its own CI job, on its own image --",
    "not here)\n\n")

for (name in selected) {
  available[[name]]()
}

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
